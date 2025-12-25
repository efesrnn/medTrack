import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationOffsetKey = 'notification_offset';

  // --- BAŞLATMA ---
  static Future<void> initializeNotifications() async {
    await Alarm.init();
  }

  // --- İZİN İSTEME (GÜÇLENDİRİLMİŞ) ---
  static Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      // 1. Temel Bildirim İzni
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // 2. Tam Zamanlı Alarm İzni (Android 12+)
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }

      // 3. KRİTİK: EKRAN ÜZERİNDE GÖSTERME İZNİ (Samsung ekran uyanması için)
      // Bu izin olmadan kilit ekranı açılmaz!
      if (await Permission.systemAlertWindow.isDenied) {
        await Permission.systemAlertWindow.request();
      }
    }
  }

  // --- ALARMLARI PLANLA ---
  Future<void> scheduleMedicationNotifications(BuildContext context, List<Map<String, dynamic>> sections) async {
    final prefs = await SharedPreferences.getInstance();
    final bool notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? false;
    final int offsetMinutes = prefs.getInt(_notificationOffsetKey) ?? 0;

    // Çakışmayı önlemek için eski tüm alarmları temizle
    await Alarm.stopAll();

    if (!notificationsEnabled) {
      debugPrint("Alarmlar kapalı.");
      return;
    }

    // Ses dosyası seçimi (Dil desteği)
    String currentLang = context.locale.languageCode;
    String soundPath = (currentLang == 'tr')
        ? 'assets/alarms/alarm_tr.mp3'
        : 'assets/alarms/alarm_en.mp3';

    int alarmIdCounter = 1000;

    for (var section in sections) {
      final bool isActive = section['isActive'] ?? false;

      if (isActive) {
        final String name = section['name'];
        final List<TimeOfDay> times = section['times'] != null
            ? List<TimeOfDay>.from(section['times'])
            : [];

        for (var t in times) {
          final now = DateTime.now();
          DateTime scheduledDate = DateTime(now.year, now.month, now.day, t.hour, t.minute);

          if (offsetMinutes > 0) {
            scheduledDate = scheduledDate.subtract(Duration(minutes: offsetMinutes));
          }

          if (scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          }

          final alarmSettings = AlarmSettings(
            id: alarmIdCounter++,
            dateTime: scheduledDate,
            assetAudioPath: soundPath,
            loopAudio: true,
            vibrate: true,
            volume: 1.0,
            fadeDuration: 3.0,

            // Bildirim Ayarları (Alarm 4.x Formatı)
            notificationSettings: NotificationSettings(
              title: "medicine_time_title".tr(),
              body: "medicine_time_body".tr(args: [name]),
              stopButton: "stop_alarm".tr(),
              icon: 'notification_bar_icon', // drawable klasöründe varsa
            ),

            // Ekranı uyandırma ayarı
            androidFullScreenIntent: true,
          );

          await Alarm.set(alarmSettings: alarmSettings);
          debugPrint("Alarm kuruldu: $name - $scheduledDate (ID: $alarmIdCounter)");
        }
      }
    }
  }

  Future<void> saveNotificationSettings({required bool enabled, required int offset}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
    await prefs.setInt(_notificationOffsetKey, offset);
  }

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_notificationsEnabledKey) ?? false,
      'offset': prefs.getInt(_notificationOffsetKey) ?? 0,
    };
  }
}