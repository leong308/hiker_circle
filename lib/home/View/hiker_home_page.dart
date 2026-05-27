import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Model/app_session.dart';
import '../../navigation/View/hiker_bottom_nav_bar.dart';

class HikerHomePage extends StatefulWidget {
  const HikerHomePage({
    super.key,
    required this.session,
    required this.onSignOut,
  });

  final AppSession session;
  final VoidCallback onSignOut;

  @override
  State<HikerHomePage> createState() => _HikerHomePageState();
}

class _HikerHomePageState extends State<HikerHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;
  int selectedTabIndex = 0;

  final List<HikerBottomNavDestination> tabs =
      HikerBottomNavBar.standardDestinations;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: tabs.length, vsync: this);
    tabController.addListener(updateTabIndex);
  }

  void updateTabIndex() {
    if (tabController.index != selectedTabIndex) {
      setState(() {
        selectedTabIndex = tabController.index;
      });
    }
  }

  void onTabTap(int index) {
    setState(() {
      selectedTabIndex = index;
    });
    tabController.animateTo(index);
  }

  @override
  void dispose() {
    tabController.removeListener(updateTabIndex);
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: TabBarView(
        controller: tabController,
        children: tabs
            .map(
              (tab) => ImageTabPage(
                label: tab.label,
                phoneNumber: widget.session.phoneNumber,
                onSignOut: tab.label == 'Me' ? widget.onSignOut : null,
              ),
            )
            .toList(),
      ),
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: selectedTabIndex,
        onDestinationSelected: onTabTap,
      ),
    );
  }
}

class ImageTabPage extends StatelessWidget {
  const ImageTabPage({
    super.key,
    required this.label,
    required this.phoneNumber,
    this.onSignOut,
  });

  final String label;
  final String phoneNumber;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.scaffoldBackgroundColor),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCFE5D6)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF17382C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        if (label == 'Home')
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 76),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCFE5D6)),
                ),
                child: Text(
                  phoneNumber,
                  style: const TextStyle(
                    color: Color(0xFF4E5B53),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        if (onSignOut != null)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 12),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(44),
                  onPressed: onSignOut,
                  child: Icon(
                    CupertinoIcons.square_arrow_right,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
