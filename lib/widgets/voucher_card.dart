import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/voucher.dart';

class VoucherCard extends StatelessWidget {
  final Voucher voucher;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const VoucherCard({
    super.key,
    required this.voucher,
    this.onDelete,
    this.onShare,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = voucher.isExpired
        ? const Color(0xFFFF5252)
        : voucher.isUsed
            ? const Color(0xFFFF9800)
            : voucher.disabled
                ? const Color(0xFF9E9E9E)
                : const Color(0xFF00E676);

    final statusLabel = voucher.isExpired
        ? 'Expired'
        : voucher.isUsed
            ? 'Used'
            : voucher.disabled
                ? 'Disabled'
                : 'Available';

    final priceStr = voucher.price > 0 ? '₱${voucher.price.toStringAsFixed(0)}' : 'Free';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [
                    const Color(0xFF00BFFF).withValues(alpha: 0.22),
                    const Color(0xFF7B2FBE).withValues(alpha: 0.14),
                  ]
                : [
                    const Color(0xFF16162A),
                    const Color(0xFF0D0D1E),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00BFFF).withValues(alpha: 0.7)
                : isHighlighted
                    ? const Color(0xFF00E676).withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.08),
            width: isSelected || isHighlighted ? 1.5 : 1.0,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : [
                  BoxShadow(
                    color: isSelected
                        ? const Color(0xFF00BFFF).withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.2),
                    blurRadius: isSelected ? 12 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top row: Status dot + Profile tag + (New tag)
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.6),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      statusLabel,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (voucher.isNew) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'NEW',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF00BFFF),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B2FBE).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF7B2FBE).withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      voucher.profile.isNotEmpty ? voucher.profile : 'default',
                      style: GoogleFonts.poppins(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFBB86FC),
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF00BFFF),
                      size: 16,
                    ),
                  ],
                ],
              ),

              if (voucher.customerName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person, size: 10, color: Colors.white54),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        voucher.customerName,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // Middle: Code Display
              if (voucher.password.isEmpty || voucher.password == voucher.name) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VOUCHER CODE',
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        color: Colors.white38,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      voucher.name,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF00BFFF),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'USER',
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: Colors.white38,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            voucher.name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'PASS',
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: Colors.white38,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            voucher.password,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF00BFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              // Info: Uptime / Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 11, color: Colors.white38),
                      const SizedBox(width: 3),
                      Text(
                        voucher.limitUptime.isNotEmpty ? voucher.limitUptime : 'Unlimited',
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          color: Colors.white60,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    priceStr,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF00E676),
                    ),
                  ),
                ],
              ),

              const Divider(height: 10, thickness: 0.5, color: Colors.white10),

              // Action Buttons Row (Compact Icon Buttons)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Copy Button
                  _CompactIconButton(
                    icon: Icons.copy_rounded,
                    color: const Color(0xFF00BFFF),
                    tooltip: 'Copy',
                    onTap: () {
                      final copyText = (voucher.password.isEmpty ||
                              voucher.password == voucher.name)
                          ? voucher.name
                          : '${voucher.name} / ${voucher.password}';
                      Clipboard.setData(ClipboardData(text: copyText));
                      TopToast.show(context, 'Voucher copied!', backgroundColor: const Color(0xFF00BFFF));
                    },
                  ),
                  if (onShare != null) ...[
                    const SizedBox(width: 6),
                    _CompactIconButton(
                      icon: Icons.share_rounded,
                      color: const Color(0xFF00BFFF),
                      tooltip: 'Share',
                      onTap: onShare!,
                    ),
                  ],
                  if (onDelete != null) ...[
                    const SizedBox(width: 6),
                    _CompactIconButton(
                      icon: Icons.delete_outline_rounded,
                      color: const Color(0xFFFF5252),
                      tooltip: 'Delete',
                      onTap: onDelete!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  const _CompactIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }
}
