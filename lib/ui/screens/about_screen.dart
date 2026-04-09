import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';

import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// LaTeX support (based on markdown_widget example)
// ---------------------------------------------------------------------------

const _latexTag = 'latex';

final SpanNodeGeneratorWithTag _latexGenerator = SpanNodeGeneratorWithTag(
  tag: _latexTag,
  generator: (e, config, visitor) =>
      _LatexNode(e.attributes, e.textContent, config),
);

class _LatexSyntax extends m.InlineSyntax {
  _LatexSyntax() : super(r'(\$\$[\s\S]+?\$\$)|(\$.+?\$)');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final matchValue = match.input.substring(match.start, match.end);
    String content = '';
    bool isInline = true;
    const blockSyntax = '\$\$';
    const inlineSyntax = '\$';
    if (matchValue.startsWith(blockSyntax) &&
        matchValue.endsWith(blockSyntax) &&
        matchValue != blockSyntax) {
      content = matchValue.substring(2, matchValue.length - 2);
      isInline = false;
    } else if (matchValue.startsWith(inlineSyntax) &&
        matchValue.endsWith(inlineSyntax) &&
        matchValue != inlineSyntax) {
      content = matchValue.substring(1, matchValue.length - 1);
    }
    final el = m.Element.text(_latexTag, matchValue);
    el.attributes['content'] = content;
    el.attributes['isInline'] = '$isInline';
    parser.addNode(el);
    return true;
  }
}

class _LatexNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  _LatexNode(this.attributes, this.textContent, this.config);

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? '';
    final isInline = attributes['isInline'] == 'true';
    final style = parentStyle ?? config.p.textStyle;
    if (content.isEmpty) return TextSpan(style: style, text: textContent);
    final latex = Math.tex(
      content,
      mathStyle: MathStyle.text,
      textStyle: style.copyWith(color: AppColors.gray50),
      textScaleFactor: 2,
      onErrorFallback: (error) {
        return Text(textContent, style: style.copyWith(color: Colors.red));
      },
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: !isInline
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: latex),
            )
          : latex,
    );
  }
}

// ---------------------------------------------------------------------------
// About Screen
// ---------------------------------------------------------------------------

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _markdown;
  String? _error;
  bool _loading = true;
  bool _isEnglish = true;

  @override
  void initState() {
    super.initState();
    _fetchReadme();
  }

  Future<void> _fetchReadme() async {
    try {
      final file = _isEnglish ? 'README.md' : 'README_BR.md';
      final uri = Uri.base.resolve(file);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        setState(() {
          _markdown = utf8.decode(response.bodyBytes);
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
            tooltip: 'Reload',
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
                _markdown = null;
              });
              _fetchReadme();
            },
          ),
          IconButton(
            icon: const Icon(Icons.translate),
            tooltip: _isEnglish ? 'Mudar para Português' : 'Switch to English',
            onPressed: () {
              setState(() {
                _isEnglish = !_isEnglish;
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

    final config = MarkdownConfig.darkConfig.copy(
      configs: [
        H1Config(
          style: TextStyle(
            color: AppColors.gray50,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        H2Config(
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        H3Config(
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        PConfig(
          textStyle: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.7,
          ),
        ),
        LinkConfig(
          style: const TextStyle(
            color: AppColors.accent,
            decoration: TextDecoration.underline,
          ),
        ),
        PreConfig.darkConfig.copy(
          decoration: BoxDecoration(
            color: AppColors.gray900,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.gray800),
          ),
          padding: const EdgeInsets.all(16),
        ),
        CodeConfig(
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: AppColors.accent,
            backgroundColor: AppColors.gray850,
          ),
        ),
        BlockquoteConfig(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
        ),
        TableConfig(
          headerStyle: TextStyle(
            color: AppColors.gray50,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          bodyStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          border: TableBorder.all(color: AppColors.gray800, width: 1),
        ),
      ],
    );

    return MarkdownWidget(
      data: _markdown!,
      selectable: true,
      padding: const EdgeInsets.all(24),
      config: config,
      markdownGenerator: MarkdownGenerator(
        inlineSyntaxList: [_LatexSyntax()],
        generators: [_latexGenerator],
      ),
    );
  }
}
