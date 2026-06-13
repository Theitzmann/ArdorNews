import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:async'; // Necessário para StreamSubscription e Timer
import 'dart:ui'; // Para BackdropFilter (Glassmorphism)
import 'notification_service.dart';
import 'package:audio_service/audio_service.dart';
import 'audio_handler.dart';

const String apiUrl = 'https://ardornews-production.up.railway.app';
const String supabaseAudioBaseUrl =
    'https://rgjcuvvxcdosivjnajns.supabase.co/storage/v1/object/public/audios';

late ArdorAudioHandler audioHandler;

// --- DESIGN SYSTEM ---
// Central palette — never change without explicit instruction.
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

  // Must complete before runApp: audioHandler is used in HomeScreen.initState
  audioHandler = await AudioService.init(
    builder: () => ArdorAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ardornews.audio',
      androidNotificationChannelName: 'Ardor News Audio',
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(const ArdorApp());

  // Deferred past the first frame: timezone loading and the Android 13+
  // permission dialog don't need to block app startup (faster cold start,
  // and the dialog shows over the rendered app instead of a blank screen).
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
        // Adicionando tema de texto global com sombra para legibilidade e estilo
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

  // Per-episode caches — transcripts and bullets are immutable once
  // published, so a second open never needs to hit the network again
  final Map<String, String> _transcricaoCache = {};
  final Map<String, String> _bulletsCache = {};
  bool _playerVisivel = false;
  bool _audioSelecionado = false;

  bool _transcricaoAberta = false;
  bool _notificacoesAtivas = true;
  bool _bellAnimating = false; // drives the bell tap scale bounce
  bool _carregando = true; // true while the episode list is being fetched
  final Set<String> _mesesExpandidos = {};

  late AnimationController _pulseController;
  late AnimationController _listFadeController;

  // Stream subscriptions stored so they can be cancelled in dispose()
  late final StreamSubscription<PlayerState> _playerStateSub;
  // Syncs _tocando with the real player state (OS/lock-screen events)
  late StreamSubscription<bool> _playingStateSub;

  // Cached result of _agruparPorMes() — rebuilt after each list fetch
  Map<String, List<Map<String, String>>> _gruposPorMes = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _listFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _verificarStatus();
    _carregarLista();

    // Expand the current month's group by default so today's episode is visible
    final chaveHoje =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    _mesesExpandidos.add(chaveHoje);

    final hoje = DateTime.now();
    _nomeAudioAtual =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}.mp3';
    _carregarBullets(_nomeAudioAtual);

    // Position/duration deliberately have no setState listeners: those values
    // update several times per second and would rebuild the whole screen.
    // The progress bar reads them through a scoped StreamBuilder instead.
    _playerStateSub = audioHandler.player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _tocando = false);
      }
    });

    // Keep _tocando in sync with the real player state so that OS-driven
    // pause/resume events (lock screen, headphones, phone calls) are reflected
    // in the UI without going through the in-app controls. distinct() ensures
    // we only rebuild when playing actually flips, not on every player event.
    _playingStateSub = audioHandler.playbackState
        .map((state) => state.playing)
        .distinct()
        .listen((playing) {
          if (!mounted) return;
          setState(() => _tocando = playing);
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
        _carregando = false; // list has finished loading
        // Pre-group by month so the ListView builder doesn't recompute on every frame
        _gruposPorMes = _agruparPorMes();
      });
      _listFadeController.forward();
    } catch (e) {
      debugPrint('Erro ao carregar lista: $e');
      if (!mounted) return;
      setState(() => _carregando = false); // stop spinner even on error
    }
  }

  /// Re-fetches the episode list and today's status (pull-to-refresh / retry).
  Future<void> _atualizar() {
    return Future.wait([_carregarLista(), _verificarStatus()]);
  }

  Future<void> _carregarBullets(String nomeAudio) async {
    // Serve from cache when this episode's bullets were already fetched
    final emCache = _bulletsCache[nomeAudio];
    if (emCache != null) {
      setState(() => _bulletsAtual = emCache);
      return;
    }
    try {
      final response = await http.get(Uri.parse('$apiUrl/bullets/$nomeAudio'));
      final data = jsonDecode(response.body);
      if (!mounted) return;
      final bullets = (data['bullets'] ?? '') as String;
      // Only cache non-empty results: today's episode may not have
      // bullets yet while the daily pipeline is still running
      if (bullets.isNotEmpty) _bulletsCache[nomeAudio] = bullets;
      setState(() => _bulletsAtual = bullets);
    } catch (e) {
      debugPrint('Erro ao carregar bullets: $e');
    }
  }

  void _abrirTranscricao(String nomeAudio) {
    if (_transcricaoAberta) return;
    _transcricaoAberta = true; // guard only — no rebuild needed here

    // null = still loading (sheet shows a spinner); set once the text is ready
    final conteudo = ValueNotifier<String?>(_transcricaoCache[nomeAudio]);

    // Fire the fetch WITHOUT awaiting it, so the sheet opens instantly and
    // fills in when the response arrives — previously the await ran first
    // and the user saw nothing until the whole round trip completed.
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
                  // Rebuilds only this area when the transcript arrives
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
      // Release the reopen guard. The notifier is intentionally not disposed:
      // the in-flight fetch may still resolve after the sheet closes (filling
      // the cache for next time), and writing to a disposed notifier throws.
      _transcricaoAberta = false;
    });
  }

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
        await audioHandler.play();
      }
    } else {
      setState(() {
        _nomeAudioAtual = nomeAudio;
        _bulletsAtual = '';
        _audioSelecionado = true;
        _playerVisivel = true;
      });
      _carregarBullets(nomeAudio);
      await audioHandler.stop();
      try {
        await audioHandler.loadUrl(url, titulo, emoji: emoji);
      } catch (e) {
        // If the URL fails to load, hide the player entirely and tell the
        // user — otherwise the footer would stay visible with no audio.
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

  Future<void> _tocarOuPausar() async {
    if (_tocando) {
      await audioHandler.pause();
    } else {
      await audioHandler.play();
    }
  }

  Future<void> _toggleNotificacoes() async {
    if (_notificacoesAtivas) {
      await NotificationService.cancelarNotificacoes();
      setState(() => _notificacoesAtivas = false);
    } else {
      await NotificationService.agendarNotificacaoDiaria();
      setState(() => _notificacoesAtivas = true);
    }
  }

  // --- HELPERS ---

  // Skip forward 10 seconds — matches the replay_10/forward_10 icons
  // (Material has no 15s glyph, so the interval follows the icon)
  void _avancar10s() {
    final duracao = audioHandler.player.duration ?? Duration.zero;
    final novaPosicao =
        audioHandler.player.position + const Duration(seconds: 10);
    audioHandler.seek(novaPosicao > duracao ? duracao : novaPosicao);
  }

  // Skip back 10 seconds
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

  /// Groups _audios by year-month key (e.g. "2025-05"), sorted entries descending.
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

  /// Returns a human-readable month label from a "yyyy-MM" key, e.g. "Maio 2025".
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
    // Cancel stream subscriptions to prevent memory leaks
    _playerStateSub.cancel();
    _playingStateSub.cancel();
    _pulseController.dispose();
    _listFadeController.dispose();
    super.dispose();
  }

  // --- UI ---

  /// Builds a single episode card for the grouped list.
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
                // Emoji thumbnail
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
                // Title and date
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
                // Play/Pause button
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

  /// Builds the sticky player footer shown when an episode is active.
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
                // Loading indicator — shown while audio is buffering/loading
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
                        _bulletsAtual.isEmpty
                            ? _mensagem
                            : 'Principais destaques',
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

                if (_bulletsAtual.isNotEmpty) ...[
                  // Altura limitada + scroll: bullets longos faziam o footer
                  // ultrapassar o espaço do ecrã ("BOTTOM OVERFLOWED BY 107
                  // PIXELS"). Com ConstrainedBox + SingleChildScrollView nada
                  // fica cortado — linhas extra ficam acessíveis por scroll.
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
                        // Unused index dropped — only the line text is needed
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

                // Barra de progresso — wrapped in a StreamBuilder so the
                // several-times-per-second position ticks rebuild only this
                // small section, not the whole screen via setState
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
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

          // Ambient glow — top right (orange)
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

          // Ambient glow — bottom left (purple)
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

          // Botão de notificação no canto superior esquerdo — with scale bounce on tap
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: _bellAnimating ? 1.3 : 1.0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              onEnd: () {
                // Reset flag after the scale-up so it bounces back to 1.0
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
                  // Show spinner while the list is being fetched
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
                  // Empty state — no episodes (or the fetch failed), with retry
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
                  // Episode list grouped by month
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
                              // AlwaysScrollable parent lets pull-to-refresh work
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
                                    // Month header — tap to expand/collapse
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
                                    // Episode cards — animated expand/collapse
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
                if (_playerVisivel) _buildPlayerFooter(),
              ],
            ),
          ),

          // Floating restore button — shown when player is minimised
          if (!_playerVisivel)
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
