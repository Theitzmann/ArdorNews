import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:async'; // Necessário para StreamSubscription e Timer
import 'dart:ui'; // Para BackdropFilter (Glassmorphism)
import 'notification_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_handler.dart';

const String apiUrl = 'https://ardornews-production.up.railway.app';
const String supabaseAudioBaseUrl =
    'https://rgjcuvvxcdosivjnajns.supabase.co/storage/v1/object/public/audios';

late ArdorAudioHandler audioHandler;

// Paleta de cores do app
class _AppColors {
  static const background = Color(0xFF0F121E);
  static const accent = Color(0xFFFF6B35);
  static const cardBg = Color(0xFF1a1f35);
  static const darkNavy = Color(0xFF0d0f1a);
  static const purple = Color(0xFF4A35FF);
  static const cardThumbnailBg = Color(0xFF2a2f45);
  static const accentHighlight = Color(0xFFFF8B55);
  static const midnightPurple = Color(0xFF1a1035);
  static const chipBg = Color(0xFF1B1A30);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Precisa terminar antes do runApp (usado na tela inicial)
  audioHandler = await AudioService.init(
    builder: () => ArdorAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ardornews.audio',
      androidNotificationChannelName: 'Ardor News Audio',
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(const ArdorApp());

  // Adiado pro pós-primeiro-frame, pra não travar a abertura do app
  unawaited(
    NotificationService.init().then(
      (_) => NotificationService.agendarNotificacaoDiaria(),
    ),
  );
}

class ArdorApp extends StatelessWidget {
  const ArdorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ardor News',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _AppColors.accent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _AppColors.background,
        // Tema de texto global com sombra
        textTheme: GoogleFonts.interTextTheme(
          const TextTheme(
            titleLarge: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: Colors.black45,
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
            bodyMedium: TextStyle(
              color: _AppColors.accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 4,
                ),
              ],
            ),
            bodySmall: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // --- STATE ---
  bool _pronto = false;
  bool _tocando = false;
  String _mensagem = 'Verificando...';
  List<Map<String, String>> _audios = [];
  String _nomeAudioAtual = '';
  String _bulletsAtual = '';
  // Destaques clicáveis do episódio atual (cai na lista simples se não houver)
  List<Map<String, dynamic>> _destaquesAtual = [];
  // True enquanto carrega os destaques do episódio tocado
  bool _carregandoBullets = false;

  // Edições favoritadas (salvas no aparelho), mostradas no menu lateral
  final Set<String> _favoritos = {};
  static const _favoritosKey = 'favoritos';
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Cache por episódio (o conteúdo é imutável, então não rebusca)
  final Map<String, String> _transcricaoCache = {};
  final Map<String, String> _bulletsCache = {};
  final Map<String, List<Map<String, dynamic>>> _destaquesCache = {};
  bool _playerVisivel = false;
  bool _audioSelecionado = false;

  bool _transcricaoAberta = false;
  bool _notificacoesAtivas = true;
  bool _bellAnimating = false; // anima o "pulo" do sininho ao tocar
  bool _carregando = true; // true enquanto a lista carrega
  final Set<String> _mesesExpandidos = {};

  late AnimationController _pulseController;
  late AnimationController _listFadeController;

  // Assinaturas de stream, canceladas no dispose()
  late final StreamSubscription<PlayerState> _playerStateSub;
  late StreamSubscription<bool> _playingStateSub;

  // Resultado de _agruparPorMes() em cache
  Map<String, List<Map<String, String>>> _gruposPorMes = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // O pulso roda só enquanto toca (ver _sincronizarPulso), pra não repintar à toa

    _listFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _verificarStatus();
    _carregarLista();
    _carregarFavoritos();

    // Abre o mês atual por padrão, pra mostrar o episódio de hoje
    final chaveHoje =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    _mesesExpandidos.add(chaveHoje);

    final hoje = DateTime.now();
    final nomeHoje =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}.mp3';

    // Reidrata o player se o áudio ainda está carregado em segundo plano
    // (ex.: a Activity foi recriada enquanto tocava), pra não voltar com os
    // controles mortos
    final mediaAtiva = audioHandler.mediaItem.value;
    if (mediaAtiva != null && audioHandler.player.audioSource != null) {
      _nomeAudioAtual = mediaAtiva.id.split('/').last;
      _audioSelecionado = true;
      _playerVisivel = true;
      _tocando = audioHandler.player.playing;
    } else {
      _nomeAudioAtual = nomeHoje;
    }
    _carregarBullets(_nomeAudioAtual);
    _carregarDestaques(_nomeAudioAtual);

    // Sem listener de posição aqui: mudaria várias vezes por segundo e
    // rebuildaria a tela toda (a barra usa um StreamBuilder isolado)
    _playerStateSub = audioHandler.player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _tocando = false);
      }
    });

    // Mantém _tocando em sincronia com o player real (lock screen, fones,
    // ligações). Ouve o playingStream do just_audio, que é a fonte da verdade
    // e devolve o valor atual ao se inscrever — então o ícone fica certo até
    // depois da Activity ser recriada.
    _playingStateSub = audioHandler.player.playingStream.distinct().listen((
      playing,
    ) {
      if (!mounted) return;
      setState(() {
        _tocando = playing;
        // Reativa os controles só quando o áudio começa a tocar (nunca em
        // stop/pause), pra fechar o player nunca ser desfeito
        if (playing && !_audioSelecionado) {
          _audioSelecionado = true;
          final media = audioHandler.mediaItem.value;
          if (media != null) _nomeAudioAtual = media.id.split('/').last;
        }
      });
      _sincronizarPulso(playing);
    });
  }

  // --- API ---

  Future<void> _verificarStatus() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/status'));
      final data = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _pronto = data['pronto'] ?? false;
        _mensagem = _pronto
            ? 'Notícias de hoje prontas!'
            : (data['mensagem'] ?? 'Aguardando notícias...');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensagem = 'Erro ao conectar.');
    }
  }

  Future<void> _carregarLista() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/lista'));
      final data = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _audios = List<Map<String, String>>.from(
          data['audios'].map(
            (a) => {
              'nome': a['nome'].toString(),
              'titulo': a['titulo'].toString(),
              'emoji': a['emoji']?.toString() ?? '📰',
            },
          ),
        );
        _audios.sort((a, b) => b['nome']!.compareTo(a['nome']!));
        _carregando = false;
        // Agrupa por mês adiantado, pra lista não recalcular a cada frame
        _gruposPorMes = _agruparPorMes();
      });
      _listFadeController.forward();
    } catch (e) {
      debugPrint('Erro ao carregar lista: $e');
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  // Recarrega a lista e o status (puxar pra atualizar)
  Future<void> _atualizar() {
    return Future.wait([_carregarLista(), _verificarStatus()]);
  }

  // Busca a lista simples de destaques (usada como fallback)
  Future<void> _carregarBullets(String nomeAudio) async {
    final emCache = _bulletsCache[nomeAudio];
    if (emCache != null) {
      setState(() {
        _bulletsAtual = emCache;
        _carregandoBullets = false;
      });
      return;
    }
    try {
      final response = await http.get(Uri.parse('$apiUrl/bullets/$nomeAudio'));
      final data = jsonDecode(response.body);
      if (!mounted) return;
      final bullets = (data['bullets'] ?? '') as String;
      // Só guarda em cache se não estiver vazio (hoje pode ainda não ter)
      if (bullets.isNotEmpty) _bulletsCache[nomeAudio] = bullets;
      setState(() {
        _bulletsAtual = bullets;
        _carregandoBullets = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar bullets: $e');
      if (mounted) setState(() => _carregandoBullets = false);
    }
  }

  // Busca os destaques detalhados do episódio (vazio = edição antiga)
  Future<void> _carregarDestaques(String nomeAudio) async {
    final emCache = _destaquesCache[nomeAudio];
    if (emCache != null) {
      setState(() => _destaquesAtual = emCache);
      return;
    }
    try {
      // Lê direto do bucket público (igual ao áudio); 404 cai no catch e
      // mantém o fallback
      final nomeJson = nomeAudio.replaceAll('.mp3', '_destaques.json');
      final response = await http.get(
        Uri.parse('$supabaseAudioBaseUrl/$nomeJson'),
      );
      if (!mounted || response.statusCode != 200) return;
      final lista = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (lista.isNotEmpty) _destaquesCache[nomeAudio] = lista;
      setState(() => _destaquesAtual = lista);
    } catch (e) {
      debugPrint('Erro ao carregar destaques: $e');
    }
  }

  // --- FAVORITOS ---

  Future<void> _carregarFavoritos() async {
    final prefs = await SharedPreferences.getInstance();
    final salvos = prefs.getStringList(_favoritosKey) ?? [];
    if (!mounted) return;
    setState(() => _favoritos
      ..clear()
      ..addAll(salvos));
  }

  Future<void> _toggleFavorito(String nomeAudio) async {
    setState(() {
      if (!_favoritos.remove(nomeAudio)) _favoritos.add(nomeAudio);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritosKey, _favoritos.toList());
  }

  // Abre a notícia completa do destaque + o "o que aprender"
  void _abrirDetalheDestaque(Map<String, dynamic> destaque) {
    final emoji = (destaque['emoji'] ?? '📰').toString();
    final titulo = (destaque['titulo'] ?? '').toString();
    final resumo = (destaque['resumo'] ?? '').toString();
    final aprender = (destaque['aprender'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: _AppColors.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        // Abre grande e dá snap entre dois tamanhos, pra rolar direto o conteúdo
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        snap: true,
        snapSizes: const [0.7, 0.92],
        builder: (context, scrollController) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        titulo,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  // Isola a rolagem do fundo borrado pesado, pra não repintar junto
                  child: RepaintBoundary(
                    child: SingleChildScrollView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resumo,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.7,
                          ),
                        ),
                        if (aprender.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _AppColors.accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _AppColors.accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.lightbulb_outline_rounded,
                                      color: _AppColors.accent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'O QUE APRENDER',
                                      style: GoogleFonts.inter(
                                        color: _AppColors.accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  aprender,
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 15,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Abre a transcrição completa do episódio
  void _abrirTranscricao(String nomeAudio) {
    if (_transcricaoAberta) return;
    _transcricaoAberta = true;

    // null = ainda carregando (mostra spinner)
    final conteudo = ValueNotifier<String?>(_transcricaoCache[nomeAudio]);

    // Dispara a busca sem await, pra sheet abrir na hora
    if (conteudo.value == null) {
      http
          .get(Uri.parse('$apiUrl/transcricao/$nomeAudio'))
          .then((response) {
            final data = jsonDecode(response.body);
            final texto = data['transcricao'] as String?;
            if (texto != null) _transcricaoCache[nomeAudio] = texto;
            conteudo.value = texto ?? 'Transcrição não disponível.';
          })
          .catchError((e) {
            debugPrint('Erro ao carregar transcrição: $e');
            conteudo.value = 'Erro ao carregar transcrição.';
          });
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: _AppColors.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        // Fade + slide suave do conteúdo enquanto a sheet sobe — o modal já
        // anima a subida; isto evita que o texto "apareça seco" lá dentro
        builder: (context, scrollController) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transcrição',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  // Atualiza só esta área quando a transcrição chega
                  child: ValueListenableBuilder<String?>(
                    valueListenable: conteudo,
                    builder: (context, texto, _) {
                      if (texto == null) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: _AppColors.accent,
                            strokeWidth: 2,
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          texto,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.7,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      // Libera a trava de reabertura (o notifier não é descartado de propósito,
      // pois a busca pode terminar depois de fechar)
      _transcricaoAberta = false;
    });
  }

  // Toca/pausa o episódio tocado, ou troca de episódio e carrega o novo
  Future<void> _tocarAudio(String url) async {
    final nomeAudio = url.split('/').last;
    final audio = _audios.firstWhere(
      (a) => a['nome'] == nomeAudio,
      orElse: () => {'titulo': 'Ardor News', 'emoji': '📰'},
    );
    final titulo = audio['titulo'] ?? 'Ardor News';
    final emoji = audio['emoji'] ?? '📰';

    if (_nomeAudioAtual == nomeAudio &&
        audioHandler.player.audioSource != null) {
      if (_tocando) {
        await audioHandler.pause();
      } else {
        // Recomeça do início se o episódio terminou (estado "completed" ignora play)
        if (audioHandler.player.processingState ==
            ProcessingState.completed) {
          await audioHandler.seek(Duration.zero);
        }
        await audioHandler.play();
      }
    } else {
      setState(() {
        _nomeAudioAtual = nomeAudio;
        _bulletsAtual = '';
        _destaquesAtual = [];
        _carregandoBullets = true;
        _audioSelecionado = true;
        _playerVisivel = true;
      });
      _carregarBullets(nomeAudio);
      _carregarDestaques(nomeAudio);
      await audioHandler.stop();
      try {
        await audioHandler.loadUrl(url, titulo, emoji: emoji);
      } catch (e) {
        // Se a URL falhar, esconde o player e avisa o usuário
        debugPrint('Erro ao carregar áudio: $e');
        if (!mounted) return;
        setState(() {
          _tocando = false;
          _audioSelecionado = false;
          _playerVisivel = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao carregar o áudio. Tente novamente.'),
          ),
        );
        return;
      }
      await audioHandler.play();
    }
  }

  // Roda o pulso do play só enquanto toca (para o repaint ao pausar)
  void _sincronizarPulso(bool playing) {
    if (playing) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  Future<void> _tocarOuPausar() async {
    if (_tocando) {
      await audioHandler.pause();
    } else {
      // Recomeça do início se o episódio terminou (estado "completed" ignora play)
      if (audioHandler.player.processingState == ProcessingState.completed) {
        await audioHandler.seek(Duration.zero);
      }
      await audioHandler.play();
    }
  }

  // Liga/desliga a notificação diária
  Future<void> _toggleNotificacoes() async {
    if (_notificacoesAtivas) {
      await NotificationService.cancelarNotificacoes();
      setState(() => _notificacoesAtivas = false);
    } else {
      await NotificationService.agendarNotificacaoDiaria();
      setState(() => _notificacoesAtivas = true);
      // Alarme agendado; pede isenção de bateria pra chegar com o app fechado
      final isento = await NotificationService.verificarOtimizacaoBateria();
      if (!isento && mounted) _mostrarDialogoBateria();
    }
  }

  // Pede pra tirar a restrição de bateria (pra notificação das 11h funcionar)
  void _mostrarDialogoBateria() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          'Permissão necessária',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Para receber a notificação das 11h mesmo com o app fechado, '
          'permita que o Ardor News funcione sem restrições de bateria.',
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Agora não',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              NotificationService.solicitarIgnorarOtimizacao();
            },
            child: Text(
              'Permitir',
              style: GoogleFonts.inter(
                color: _AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---

  // Avança 10 segundos
  void _avancar10s() {
    final duracao = audioHandler.player.duration ?? Duration.zero;
    final novaPosicao =
        audioHandler.player.position + const Duration(seconds: 10);
    audioHandler.seek(novaPosicao > duracao ? duracao : novaPosicao);
  }

  // Volta 10 segundos
  void _voltar10s() {
    final novaPosicao =
        audioHandler.player.position - const Duration(seconds: 10);
    audioHandler.seek(
      novaPosicao < Duration.zero ? Duration.zero : novaPosicao,
    );
  }

  String _formatarTempo(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seg = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$seg';
  }

  String _formatarDiaSemana(String nome) {
    final data = nome.replaceAll('.mp3', '');
    final partes = data.split('-');
    if (partes.length != 3) return nome;
    final dataAudio = DateTime(
      int.parse(partes[0]),
      int.parse(partes[1]),
      int.parse(partes[2]),
    );
    const dias = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    return dias[dataAudio.weekday - 1];
  }

  String _formatarDataCurta(String nome) {
    final data = nome.replaceAll('.mp3', '');
    final partes = data.split('-');
    if (partes.length != 3) return '';
    final hoje = DateTime.now();
    final dataAudio = DateTime(
      int.parse(partes[0]),
      int.parse(partes[1]),
      int.parse(partes[2]),
    );
    final diff = hoje.difference(dataAudio).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    return '${partes[2]}/${partes[1]}';
  }

  String _urlAudio(String nome) {
    return '$supabaseAudioBaseUrl/$nome';
  }

  // Agrupa os áudios por ano-mês (ex: "2025-05")
  Map<String, List<Map<String, String>>> _agruparPorMes() {
    final Map<String, List<Map<String, String>>> grupos = {};
    for (final audio in _audios) {
      final partes = audio['nome']!.replaceAll('.mp3', '').split('-');
      if (partes.length != 3) continue;
      final chave = '${partes[0]}-${partes[1]}';
      grupos.putIfAbsent(chave, () => []);
      grupos[chave]!.add(audio);
    }
    return grupos;
  }

  // Devolve o nome do mês a partir da chave "yyyy-MM" (ex: "Maio 2025")
  String _labelMes(String chave) {
    const meses = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final partes = chave.split('-');
    final mes = int.parse(partes[1]);
    return '${meses[mes - 1]} ${partes[0]}';
  }

  @override
  void dispose() {
    // Cancela as assinaturas pra evitar vazamento de memória
    _playerStateSub.cancel();
    _playingStateSub.cancel();
    _pulseController.dispose();
    _listFadeController.dispose();
    super.dispose();
  }

  // --- UI ---

  // Monta um card de episódio da lista
  Widget _buildAudioCard(Map<String, String> audio) {
    final nome = audio['nome']!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _tocarAudio(_urlAudio(nome)),
          highlightColor: _AppColors.accent.withValues(alpha: 0.1),
          splashColor: _AppColors.accent.withValues(alpha: 0.2),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Miniatura do emoji
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _AppColors.cardThumbnailBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      audio['emoji'] ?? '📰',
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Título e data
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatarDiaSemana(nome).toUpperCase(),
                            style: GoogleFonts.inter(
                              color: _AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatarDataCurta(nome),
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        audio['titulo'] ?? 'Resumo Diário de Tecnologia',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Botão de favoritar
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleFavorito(nome),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _favoritos.contains(nome)
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _favoritos.contains(nome)
                          ? _AppColors.accent
                          : Colors.white38,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                // Botão de play/pause
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tocarAudio(_urlAudio(nome)),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        (_nomeAudioAtual == nome && _tocando)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(
                          _nomeAudioAtual == nome && _tocando,
                        ),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Uma linha de destaque clicável no rodapé — abre a notícia completa
  Widget _buildDestaqueRow(Map<String, dynamic> destaque) {
    final emoji = (destaque['emoji'] ?? '📰').toString();
    final titulo = (destaque['titulo'] ?? '').toString();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirDetalheDestaque(destaque),
        splashColor: _AppColors.accent.withValues(alpha: 0.15),
        highlightColor: _AppColors.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: _AppColors.accent.withValues(alpha: 0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Monta o player fixo no rodapé, mostrado quando há um episódio ativo
  Widget _buildPlayerFooter() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(32),
              // Sombra reforçada no box do player
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: -5,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador de carregamento, enquanto o áudio está carregando
                StreamBuilder<AudioProcessingState>(
                  stream: audioHandler.playbackState
                      .map((s) => s.processingState)
                      .distinct(),
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final isLoading =
                        state == AudioProcessingState.loading ||
                        state == AudioProcessingState.buffering;
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: isLoading
                          ? LinearProgressIndicator(
                              color: _AppColors.accent,
                              backgroundColor: Colors.transparent,
                              minHeight: 2,
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),

                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _playerVisivel = false),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      color: Colors.white54,
                      iconSize: 28,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                    ),
                    Expanded(
                      child: Text(
                        (_destaquesAtual.isNotEmpty || _bulletsAtual.isNotEmpty)
                            ? 'Principais destaques'
                            // Enquanto carrega os destaques, mostra um título
                            // neutro (não o _mensagem, que é o status de "hoje
                            // está pronto?" e piscaria aqui)
                            : (_carregandoBullets
                                  ? 'Carregando destaques...'
                                  : _mensagem),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _audioSelecionado
                          ? () => _abrirTranscricao(_nomeAudioAtual)
                          : null,
                      icon: const Icon(Icons.article_outlined),
                      color: _AppColors.accent,
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_destaquesAtual.isNotEmpty) ...[
                  // Destaques clicáveis — cada um abre a notícia completa.
                  // Altura limitada e rolável pra um dia cheio não estourar
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 170),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _destaquesAtual
                            .map((d) => _buildDestaqueRow(d))
                            .toList(),
                      ),
                    ),
                  ),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 24,
                  ),
                ] else if (_bulletsAtual.isNotEmpty) ...[
                  // Para edições antigas sem _destaques.json: cai na lista
                  // simples de tópicos (não clicável)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: _bulletsAtual
                            .split('\n')
                            .where((String l) => l.trim().isNotEmpty)
                            .map((String linha) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  linha.trim(),
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),
                  ),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 24,
                  ),
                ],

                // Controles Play/Pause e Pular
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: IconButton(
                        onPressed: _audioSelecionado ? _voltar10s : null,
                        icon: const Icon(Icons.replay_10_rounded),
                        color: Colors.white70,
                        disabledColor: Colors.white24,
                        iconSize: 32,
                        splashRadius: 24,
                      ),
                    ),
                    const SizedBox(width: 24),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale = _tocando
                            ? 1.0 + (_pulseController.value * 0.08)
                            : 1.0;
                        final isActive = _audioSelecionado;
                        return Transform.scale(
                          scale: scale,
                          child: InkWell(
                            onTap: isActive ? _tocarOuPausar : null,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            borderRadius: BorderRadius.circular(36),
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isActive
                                    ? const LinearGradient(
                                        colors: [
                                          _AppColors.accentHighlight,
                                          _AppColors.accent,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isActive
                                    ? null
                                    : Colors.white.withValues(alpha: 0.1),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: _AppColors.accent.withValues(
                                            alpha: _tocando ? 0.6 : 0.3,
                                          ),
                                          blurRadius: _tocando ? 25 : 15,
                                          spreadRadius: _tocando ? 4 : 1,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder:
                                    (
                                      Widget child,
                                      Animation<double> animation,
                                    ) {
                                      return ScaleTransition(
                                        scale: animation,
                                        child: child,
                                      );
                                    },
                                child: Icon(
                                  _tocando
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  key: ValueKey<String>(
                                    _tocando ? 'pause' : 'play',
                                  ),
                                  size: 38,
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 24),
                    Material(
                      color: Colors.transparent,
                      child: IconButton(
                        onPressed: _audioSelecionado ? _avancar10s : null,
                        icon: const Icon(Icons.forward_10_rounded),
                        color: Colors.white70,
                        disabledColor: Colors.white24,
                        iconSize: 32,
                        splashRadius: 24,
                      ),
                    ),
                  ],
                ),

                // Barra de progresso — dentro de um StreamBuilder pra que os
                // ticks de posição (várias vezes por segundo) repintem só esta
                // parte, e não a tela toda via setState
                StreamBuilder<Duration>(
                  stream: audioHandler.player.positionStream,
                  builder: (context, snapshot) {
                    final posicao = snapshot.data ?? Duration.zero;
                    final duracao =
                        audioHandler.player.duration ?? Duration.zero;
                    if (duracao.inSeconds <= 0) return const SizedBox.shrink();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                            activeTrackColor: _AppColors.accent,
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            thumbColor: Colors.white,
                            overlayColor: _AppColors.accent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: posicao.inSeconds.toDouble().clamp(
                              0,
                              duracao.inSeconds.toDouble(),
                            ),
                            min: 0,
                            max: duracao.inSeconds.toDouble(),
                            onChanged: (val) => audioHandler.seek(
                              Duration(seconds: val.toInt()),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatarTempo(posicao),
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatarTempo(duracao),
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Menu lateral com as edições favoritadas; toque numa pra tocar
  Widget _buildFavoritosDrawer() {
    final favoritos =
        _audios.where((a) => _favoritos.contains(a['nome'])).toList();
    return Drawer(
      backgroundColor: _AppColors.cardBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_rounded,
                    color: _AppColors.accent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Favoritos',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            Expanded(
              child: favoritos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bookmark_border_rounded,
                              color: Colors.white24,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma notícia favoritada',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: Colors.white38,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Toque no marcador de uma edição para guardá-la aqui.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: Colors.white24,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: favoritos.length,
                      itemBuilder: (context, i) {
                        final audio = favoritos[i];
                        final nome = audio['nome']!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.of(context).pop();
                                _tocarAudio(_urlAudio(nome));
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Text(
                                      audio['emoji'] ?? '📰',
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _formatarDataCurta(nome),
                                            style: GoogleFonts.inter(
                                              color: _AppColors.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            audio['titulo'] ??
                                                'Resumo Diário de Tecnologia',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _toggleFavorito(nome),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.bookmark_rounded,
                                          color: _AppColors.accent,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildFavoritosDrawer(),
      body: Stack(
        children: [
          // Gradiente de fundo
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _AppColors.background,
                  _AppColors.midnightPurple,
                  _AppColors.darkNavy,
                ],
              ),
            ),
          ),

          // Brilho ambiente — canto superior direito (laranja)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _AppColors.accent.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Brilho ambiente — canto inferior esquerdo (roxo)
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _AppColors.purple.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Efeito de blur leve no fundo (Glassmorphism base)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withValues(alpha: 0.1)),
          ),

          // Botão de notificação no canto superior esquerdo — com um leve quique ao tocar
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: _bellAnimating ? 1.3 : 1.0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              onEnd: () {
                // Desfaz a flag depois do aumento pra ele voltar a 1.0
                if (_bellAnimating) setState(() => _bellAnimating = false);
              },
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: GestureDetector(
                onTap: () {
                  setState(() => _bellAnimating = true);
                  _toggleNotificacoes();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Icon(
                    _notificacoesAtivas
                        ? Icons.notifications_rounded
                        : Icons.notifications_off_rounded,
                    color: _notificacoesAtivas
                        ? _AppColors.accent
                        : Colors.white38,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

          // Botão de favoritos (canto superior direito) — abre o menu lateral
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Icon(
                  Icons.bookmark_rounded,
                  color: _favoritos.isEmpty ? Colors.white38 : _AppColors.accent,
                  size: 20,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // --- CABEÇALHO ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'logo',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                _AppColors.accent.withValues(alpha: 0.8),
                                _AppColors.accent.withValues(alpha: 0.2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _AppColors.accent.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: _AppColors.background,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: Transform.scale(
                                scale: 1.45,
                                child: Image.asset(
                                  'assets/logo.png',
                                  height: 112,
                                  width: 112,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ARDOR NEWS',
                        style:
                            theme.textTheme.titleLarge, // Usa o tema com sombra
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _AppColors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Notícias rápidas do mundo da tecnologia',
                          style: theme
                              .textTheme
                              .bodyMedium, // Usa o tema com sombra
                        ),
                      ),
                    ],
                  ),
                ),

                // --- LISTA DE EDIÇÕES ANTERIORES (agrupada por mês) ---
                if (_carregando)
                  // Mostra o carregamento enquanto a lista é buscada
                  const Expanded(
                    child: Center(
                      child: Opacity(
                        opacity: 0.6,
                        child: CircularProgressIndicator(
                          color: _AppColors.accent,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else if (_audios.isEmpty)
                  // Estado vazio — sem episódios (ou a busca falhou), com opção de tentar de novo
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.newspaper_rounded,
                            color: Colors.white24,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhuma edição disponível',
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _carregando = true);
                              _atualizar();
                            },
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: _AppColors.accent,
                              size: 18,
                            ),
                            label: Text(
                              'Tentar novamente',
                              style: GoogleFonts.inter(
                                color: _AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // Lista de episódios agrupada por mês
                  Expanded(
                    child: FadeTransition(
                      opacity: _listFadeController,
                      child: Builder(
                        builder: (context) {
                          final grupos = _gruposPorMes;
                          final chaves = grupos.keys.toList()
                            ..sort((a, b) => b.compareTo(a));
                          return RefreshIndicator(
                            onRefresh: _atualizar,
                            color: _AppColors.accent,
                            backgroundColor: _AppColors.cardBg,
                            child: ListView.builder(
                              // O pai sempre rolável permite o puxar-pra-atualizar
                              // even when the list is shorter than the screen
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              itemCount: chaves.length,
                              itemBuilder: (context, i) {
                                final chave = chaves[i];
                                final expandido = _mesesExpandidos.contains(
                                  chave,
                                );
                                final episodios = grupos[chave]!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Cabeçalho do mês — toque pra abrir/fechar
                                    GestureDetector(
                                      onTap: () => setState(() {
                                        if (expandido) {
                                          _mesesExpandidos.remove(chave);
                                        } else {
                                          _mesesExpandidos.add(chave);
                                        }
                                      }),
                                      // behavior: opaque mantém a linha toda
                                      // clicável mesmo sem o Spacer/chevron à
                                      // direita
                                      behavior: HitTestBehavior.opaque,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            // Chevron à esquerda: à direita
                                            // ficava por baixo do FAB durante
                                            // o scroll
                                            Icon(
                                              expandido
                                                  ? Icons
                                                        .keyboard_arrow_up_rounded
                                                  : Icons
                                                        .keyboard_arrow_down_rounded,
                                              color: Colors.white30,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _labelMes(chave).toUpperCase(),
                                              style: GoogleFonts.inter(
                                                color: _AppColors.accent,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${episodios.length} episódio${episodios.length > 1 ? 's' : ''}',
                                              style: GoogleFonts.inter(
                                                color: Colors.white30,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Cards dos episódios — abrem/fecham com animação
                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeInOut,
                                      child: Column(
                                        children: expandido
                                            ? episodios
                                                  .map(_buildAudioCard)
                                                  .toList()
                                            : [],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // --- PLAYER FIXO NO RODAPÉ ---
                // Recolhe pra baixo (tamanho + fade + slide) ao minimizar,
                // como se o player se dobrasse em direção ao botão flutuante
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => SizeTransition(
                    sizeFactor: anim,
                    axisAlignment: -1.0,
                    child: FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                  ),
                  child: _playerVisivel
                      ? _buildPlayerFooter()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Botão flutuante de restaurar — só aparece quando há áudio ativo
          // that's been minimised. Gating on _audioSelecionado means closing
          // the player hides it entirely (no reopening a dead player).
          if (!_playerVisivel && _audioSelecionado)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              right: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_audioSelecionado)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.6,
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.chipBg.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _audios.firstWhere(
                                      (a) => a['nome'] == _nomeAudioAtual,
                                      orElse: () => {'titulo': 'Tocando agora'},
                                    )['titulo'] ??
                                    '',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Play/pause sem precisar de expandir o player —
                            // mesma lógica do botão principal
                            GestureDetector(
                              onTap: _tocarOuPausar,
                              child: Icon(
                                _tocando
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: _AppColors.accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                audioHandler.stop();
                                setState(() {
                                  _tocando = false;
                                  _audioSelecionado = false;
                                  _playerVisivel = false;
                                  // Esquece o episódio atual pra que um toque
                                  // depois (mesmo no mesmo) recarregue do zero
                                  // instead of calling play() on a stopped player.
                                  _nomeAudioAtual = '';
                                });
                              },
                              child: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  FloatingActionButton(
                    backgroundColor: _AppColors.accent,
                    elevation: 8,
                    onPressed: () => setState(() => _playerVisivel = true),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
