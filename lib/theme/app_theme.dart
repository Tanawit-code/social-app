import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ชุดสีธีมที่ให้ผู้ใช้เลือก (สีที่แอปโซเชียล/เว็บทั่วไปนิยมใช้)
class ThemePreset {
  final String id;
  final String name;
  final Color color;
  const ThemePreset(this.id, this.name, this.color);
}

const kThemePresets = <ThemePreset>[
  ThemePreset('blue', 'น้ำเงิน', Color(0xFF1877F2)),
  ThemePreset('indigo', 'คราม', Color(0xFF3F51B5)),
  ThemePreset('purple', 'ม่วง', Color(0xFF7E57C2)),
  ThemePreset('pink', 'ชมพู', Color(0xFFD81B60)),
  ThemePreset('red', 'แดง', Color(0xFFE53935)),
  ThemePreset('orange', 'ส้ม', Color(0xFFF57C00)),
  ThemePreset('green', 'เขียว', Color(0xFF2E7D32)),
  ThemePreset('teal', 'เขียวน้ำทะเล', Color(0xFF00897B)),
];

/// เก็บธีมที่เลือก และจำค่าไว้ในเครื่อง (เปิดแอปครั้งหน้ายังเป็นสีเดิม)
class AppThemeController extends ChangeNotifier {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();
  static const _prefKey = 'theme_preset';

  ThemePreset _preset = kThemePresets.first;
  ThemePreset get preset => _preset;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefKey);
      _preset = kThemePresets.firstWhere(
        (p) => p.id == id,
        orElse: () => kThemePresets.first,
      );
    } catch (_) {
      // อ่านค่าไม่ได้ = ใช้ค่าเริ่มต้น
    }
  }

  Future<void> select(ThemePreset preset) async {
    if (preset.id == _preset.id) return;
    _preset = preset;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, preset.id);
    } catch (_) {}
  }
}

ThemeData buildAppTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed);
  final radius = BorderRadius.circular(12);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // พื้นหลังเทาอ่อนอมสีธีมนิดๆ ให้การ์ดสีขาวเด่นขึ้น
    scaffoldBackgroundColor: Color.alphaBlend(
      seed.withValues(alpha: 0.05),
      const Color(0xFFF3F4F6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      space: 1,
    ),
  );
}

/// หน้าต่างเลือกสีธีม
Future<void> showThemePicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _ThemePickerSheet(),
    );

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ธีมสีของแอป',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final p in kThemePresets)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => controller.select(p),
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: p.color,
                              child: controller.preset.id == p.id
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
