import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// About screen that loads and renders README.md at runtime via HTTP.
///
/// The file is fetched from the web server root — updating README.md
/// on the server is enough; no rebuild needed.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _markdown;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchReadme();
  }

  Future<void> _fetchReadme() async {
    try {
      final uri = Uri.base.resolve('README.md');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        setState(() {
          _markdown = response.body;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load README.md (HTTP ${response.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not fetch README.md: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About AEGIS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload README.md',
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
                _markdown = null;
              });
              _fetchReadme();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text(
              'Loading README.md...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _fetchReadme();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Markdown(
      data: _markdown!,
      selectable: true,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      styleSheet: _buildStyleSheet(context),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final base = Theme.of(context).textTheme;
    return MarkdownStyleSheet(
      // Headers
      h1: base.headlineLarge?.copyWith(
        color: AppColors.gray50,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
      h2: base.headlineMedium?.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h3: base.titleLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h4: base.titleMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      // Body
      p: base.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.7),
      a: const TextStyle(
        color: AppColors.accent,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.accentSubtle,
      ),
      // Lists
      listBullet: base.bodyMedium?.copyWith(color: AppColors.textSecondary),
      // Code
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: AppColors.accent,
        backgroundColor: AppColors.gray850,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.gray900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gray800),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      // Blockquote
      blockquote: base.bodyMedium?.copyWith(
        color: AppColors.textTertiary,
        fontStyle: FontStyle.italic,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      // Table
      tableHead: base.bodyMedium?.copyWith(
        color: AppColors.gray50,
        fontWeight: FontWeight.w600,
      ),
      tableBody: base.bodyMedium?.copyWith(color: AppColors.textSecondary),
      tableBorder: TableBorder.all(color: AppColors.gray800, width: 1),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      // Horizontal rule
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.gray800, width: 1)),
      ),
      // Strong / Em
      strong: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      em: const TextStyle(
        fontStyle: FontStyle.italic,
        color: AppColors.textSecondary,
      ),
    );
  }
}
