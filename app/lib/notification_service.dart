import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    // Android 13+ exige pedir permissão de notificação em tempo de execução
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> agendarNotificacaoDiaria() async {
    await _plugin.zonedSchedule(
      0,
      '📡 Ardor News',
      'Suas notícias de hoje estão prontas!',
      _proximasOnzeHoras(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ardor_daily',
          'Notícias Diárias',
          channelDescription: 'Notificação diária das notícias',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
uiLocalNotificationDateInterpretation:
    UILocalNotificationDateInterpretation.absoluteTime,
matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelarNotificacoes() async {
    await _plugin.cancelAll();
  }

  // Verifica/pede isenção da otimização de bateria, pra notificação das 11h
  // chegar mesmo com o app fechado
  static Future<bool> verificarOtimizacaoBateria() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  static Future<void> solicitarIgnorarOtimizacao() async {
    await Permission.ignoreBatteryOptimizations.request();
  }

  static tz.TZDateTime _proximasOnzeHoras() {
    final agora = tz.TZDateTime.now(tz.local);
    var horario = tz.TZDateTime(
        tz.local, agora.year, agora.month, agora.day, 11, 0);
    if (horario.isBefore(agora)) {
      horario = horario.add(const Duration(days: 1));
    }
    return horario;
  }
}