import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import 'chat_list_screen.dart';
import 'home_feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// ข้อมูลของแต่ละแท็บบน bottom bar
class _TabItem {
  final IconData icon; // ไอคอนตอนไม่ได้เลือก
  final IconData activeIcon; // ไอคอนตอนเลือก (แบบทึบ)
  final String label; // ใช้เป็น tooltip
  final Widget Function()
  build; // สร้างหน้าของแท็บ (เรียกตอนเปิดครั้งแรกเท่านั้น)
  const _TabItem(this.icon, this.activeIcon, this.label, this.build);
}

/// โครง "หน้าหลัก" ที่มีแถบเมนูด้านล่างแบบ Facebook
/// แก้/เพิ่ม/ลดแท็บได้ที่ [_tabs] ที่เดียว
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _feedIndex = 0;
  static const _chatIndex = 2;
  static const _notiIndex = 3;
  static const _fbBlue = Color(0xFF1877F2);

  static final List<_TabItem> _tabs = [
    _TabItem(
      Icons.home_outlined,
      Icons.home,
      'หน้าแรก',
      () => const HomeFeedScreen(),
    ),
    _TabItem(Icons.search, Icons.search, 'ค้นหา', () => const SearchScreen()),
    _TabItem(
      Icons.chat_bubble_outline,
      Icons.chat_bubble,
      'แชท',
      () => const ChatListScreen(),
    ),
    _TabItem(
      Icons.notifications_none,
      Icons.notifications,
      'การแจ้งเตือน',
      () => const NotificationsScreen(),
    ),
    _TabItem(
      Icons.person_outline,
      Icons.person,
      'โปรไฟล์',
      () => const ProfileScreen(),
    ),
  ];

  final _uid = AuthService().currentUser?.uid ?? '';
  int _index = _feedIndex;

  // แท็บที่เคยเปิดแล้ว — แท็บที่ยังไม่เคยเปิดจะยังไม่ถูกสร้าง (lazy)
  final Set<int> _visited = {_feedIndex};

  @override
  void initState() {
    super.initState();
    if (_uid.isNotEmpty) {
      PushNotificationService.instance.initialize(
        uid: _uid,
        navigatorKey: PushNotificationService.navigatorKey,
      );
      PushNotificationService.instance.restoreForUser(_uid);
    }
  }

  void _select(int i) {
    if (i == _index) return;
    // เข้าหรือออกจากแท็บไหน = ถือว่าอ่านแจ้งเตือนของแท็บนั้นแล้ว
    // (กัน badge ค้างจากแจ้งเตือนที่มาตอนเปิดหน้านั้นอยู่)
    if (i == _notiIndex || _index == _notiIndex) {
      NotificationService().markRead(_uid, messages: false);
    }
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    // กด Back: ถ้าไม่ได้อยู่หน้าแรก ให้กลับไปแท็บหน้าแรกก่อน แล้วค่อยออกจากแอป
    return PopScope(
      canPop: _index == _feedIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(_feedIndex);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (int i = 0; i < _tabs.length; i++)
              // แท็บที่ยังไม่เคยเปิด = กล่องว่าง ไม่สร้างหน้าจริง
              if (_visited.contains(i)) _tabs[i].build() else const SizedBox(),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(context),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              for (int i = 0; i < _tabs.length; i++)
                Expanded(child: _buildTab(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int i) {
    final tab = _tabs[i];
    final selected = i == _index;
    final color = selected ? _fbBlue : Colors.grey.shade600;

    Widget icon = Icon(
      selected ? tab.activeIcon : tab.icon,
      color: color,
      size: 28,
    );

    // แท็บแชท = ข้อความใหม่, แท็บกระดิ่ง = ติดตาม/ไลก์/คอมเมนต์
    if (i == _notiIndex || i == _chatIndex) {
      icon = StreamBuilder<int>(
        stream: NotificationService().unreadCount(
          _uid,
          messages: i == _chatIndex,
        ),
        builder: (context, s) {
          final n = s.data ?? 0;
          // ถ้าอยู่แท็บนั้นอยู่แล้ว ไม่ต้องโชว์เลข (ออกจากแท็บแล้วจะ markRead)
          return Badge(
            isLabelVisible: n > 0 && !selected,
            label: Text(n > 99 ? '99+' : '$n'),
            child: Icon(
              selected ? tab.activeIcon : tab.icon,
              color: color,
              size: 28,
            ),
          );
        },
      );
    }

    // อ่านออกเสียง (TalkBack) ว่า "หน้าแรก, ปุ่ม, เลือกอยู่"
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      onTap: () => _select(i),
      child: InkWell(
        onTap: () => _select(i),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // เส้นสีน้ำเงินด้านบนของแท็บที่เลือก
            if (selected)
              Positioned(
                top: 0,
                left: 12,
                right: 12,
                child: Container(height: 3, color: _fbBlue),
              ),
            Tooltip(message: tab.label, child: icon),
          ],
        ),
      ),
    );
  }
}
