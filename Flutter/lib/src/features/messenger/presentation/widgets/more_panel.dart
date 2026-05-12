import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_version.dart';
import '../../domain/messenger_models.dart';
import '../messenger_page.dart';
import 'panel_header.dart';

class MorePanel extends ConsumerWidget {
  const MorePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          const PanelHeader(title: '더보기', actions: []),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
              children: [
                _AccountPanel(profile: profile),
                const SizedBox(height: 18),
                const _ServiceGrid(),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFEDEDED)),
                const SizedBox(height: 12),
                const _AppInfoRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({required this.profile});

  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.email ?? '',
                        style: const TextStyle(
                          color: Color(0xFF6F7782),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD83D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield,
                    color: Color(0xFF3757E8),
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8E8E8)),
          SizedBox(
            height: 36,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'My구독',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF9A9A9A),
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

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid();

  static const _items = [
    (Icons.mail_outline, '메일', false),
    (Icons.calendar_today_outlined, '캘린더', false),
    (Icons.cloud_outlined, '톡클라우드', false),
    (Icons.emoji_emotions_outlined, '이모티콘', false),
    (Icons.card_giftcard_outlined, '선물하기', false),
    (Icons.percent, '톡딜', false),
    (Icons.timer_outlined, '톡타이머', true),
    (Icons.science_outlined, '실험실', false),
    (Icons.credit_card_outlined, '내 결제', false),
    (Icons.campaign_outlined, '공지사항', true),
    (Icons.settings_outlined, '환경설정', false),
    (Icons.help_outline, '도움말', false),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: _items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        mainAxisExtent: 66,
      ),
      itemBuilder: (context, index) {
        final item = _items[index];

        return Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.$1, size: 25, color: Colors.black),
                if (item.$3)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF5A32),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5D6470)),
            ),
          ],
        );
      },
    );
  }
}

class _AppInfoRow extends StatelessWidget {
  const _AppInfoRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.info_outline, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'AVA 정보',
            style: TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          AppVersion.display,
          style: TextStyle(color: Color(0xFF777777), fontSize: 12),
        ),
      ],
    );
  }
}
