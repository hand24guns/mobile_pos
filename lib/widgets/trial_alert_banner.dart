import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/dashboard_service.dart';

class TrialAlertBanner extends StatelessWidget {
  final TrialStatus trialStatus;
  final VoidCallback onDismiss;
  final bool compact;

  const TrialAlertBanner({
    super.key,
    required this.trialStatus,
    required this.onDismiss,
    this.compact = false,
  });

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    String targetUrl = trialStatus.whatsappUrl;
    if (targetUrl.isEmpty) {
      final org = trialStatus.organisasi;
      final msg = Uri.encodeComponent(
          'Halo Aibipi, saya ingin berlangganan Aibipi POS.${org.isNotEmpty ? ' Company : $org' : ''}');
      targetUrl = 'https://wa.me/6282116597095?text=$msg';
    }

    final uri = Uri.parse(targetUrl);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka WhatsApp. Silakan hubungi 082116597095.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka WhatsApp. Silakan hubungi 082116597095.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = trialStatus.daysRemaining ?? 0;
    final dateStr = _formatDate(trialStatus.tglSelesai);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 620;

        final btnWhatsApp = ElevatedButton.icon(
          onPressed: () => _openWhatsApp(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 8 : 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const FaIcon(
            FontAwesomeIcons.whatsapp,
            size: 15,
            color: Colors.white,
          ),
          label: const Text(
            'Hubungi WhatsApp',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

        final btnClose = InkWell(
          onTap: onDismiss,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: Colors.grey.shade600,
            ),
          ),
        );

        final iconBox = Container(
          width: compact ? 38 : 42,
          height: compact ? 38 : 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.hourglass_bottom_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

        final badgePill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFD97706),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Sisa $days Hari',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
        );

        final subtitle = RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: compact ? 11.5 : 12,
              color: const Color(0xFF475569),
              height: 1.35,
            ),
            children: [
              const TextSpan(text: 'Berakhir pada '),
              TextSpan(
                text: dateStr.isNotEmpty ? dateStr : 'segera',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF151F2C),
                ),
              ),
              const TextSpan(
                  text: '. Perpanjang sekarang agar transaksi kasir tidak terhenti.'),
            ],
          ),
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFED7AA), width: 1.2),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFFFBEB),
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 12 : 14,
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        iconBox,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Masa Ujicoba Berakhir Segera',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF151F2C),
                                      ),
                                    ),
                                  ),
                                  btnClose,
                                ],
                              ),
                              const SizedBox(height: 4),
                              badgePill,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: subtitle,
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: btnWhatsApp,
                    ),
                  ],
                )
              : Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Masa Ujicoba Berakhir Segera',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF151F2C),
                                ),
                              ),
                              const SizedBox(width: 8),
                              badgePill,
                            ],
                          ),
                          const SizedBox(height: 3),
                          subtitle,
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    btnWhatsApp,
                    const SizedBox(width: 8),
                    btnClose,
                  ],
                ),
        );
      },
    );
  }
}
