import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../magnets/magnet_library.dart';

class MagnetLibraryPage extends StatefulWidget {
  const MagnetLibraryPage({super.key});

  @override
  State<MagnetLibraryPage> createState() => _MagnetLibraryPageState();
}

class _MagnetLibraryPageState extends State<MagnetLibraryPage> {
  final MagnetLibrary _library = MagnetLibrary();
  final TextEditingController _filterController = TextEditingController();

  List<StoredFavorite> _items = const <StoredFavorite>[];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    MagnetLibrary.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    MagnetLibrary.revision.removeListener(_load);
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<StoredFavorite> items = _filteredItems;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _FavoriteToolbar(
            controller: _filterController,
            loading: _loading,
            count: _items.length,
            onChanged: (String value) => setState(() => _filter = value),
            onAdd: () => _openEditor(null),
            onReload: _load,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (_loading)
          const SliverToBoxAdapter(
            child: _FavoriteSurface(
              child: Row(
                children: <Widget>[
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('正在读取收藏...'),
                ],
              ),
            ),
          )
        else if (items.isEmpty)
          SliverToBoxAdapter(
            child: _FavoriteEmptyState(hasFilter: _filter.trim().isNotEmpty),
          )
        else
          SliverList.separated(
            itemBuilder: (BuildContext context, int index) {
              final StoredFavorite item = items[index];
              return _FavoriteCard(
                item: item,
                onCopy: () => _copy(item),
                onEdit: () => _openEditor(item),
                onDelete: () => _delete(item),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: items.length,
          ),
      ],
    );
  }

  List<StoredFavorite> get _filteredItems {
    final String query = _filter.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items
        .where((StoredFavorite item) {
          return item.title.toLowerCase().contains(query) ||
              item.url.toLowerCase().contains(query) ||
              item.password.toLowerCase().contains(query) ||
              item.note.toLowerCase().contains(query) ||
              item.source.toLowerCase().contains(query) ||
              item.tags.any((String tag) => tag.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<StoredFavorite> items = await _library.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showSnack(error.toString());
    }
  }

  Future<void> _openEditor(StoredFavorite? item) async {
    final StoredFavorite? saved = await showDialog<StoredFavorite>(
      context: context,
      builder: (BuildContext context) => _FavoriteEditorDialog(item: item),
    );
    if (saved == null) {
      return;
    }
    try {
      await _library.upsert(saved);
      await _load();
      _showSnack(item == null ? '已添加收藏' : '已更新收藏');
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _delete(StoredFavorite item) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('删除收藏'),
              content: Text('确定删除「${item.displayTitle}」吗？'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await _library.delete(item.id);
    await _load();
    _showSnack('已删除收藏');
  }

  Future<void> _copy(StoredFavorite item) async {
    await Clipboard.setData(ClipboardData(text: item.copyText));
    _showSnack('已复制链接');
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(appSnack(message));
  }
}

class _FavoriteToolbar extends StatelessWidget {
  const _FavoriteToolbar({
    required this.controller,
    required this.loading,
    required this.count,
    required this.onChanged,
    required this.onAdd,
    required this.onReload,
  });

  final TextEditingController controller;
  final bool loading;
  final int count;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return _FavoriteSurface(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 650;
          final Widget search = SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '搜索收藏',
                suffixText: '$count 条',
              ),
            ),
          );
          final Widget add = SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: loading ? null : onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加'),
            ),
          );
          final Widget reload = SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onReload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新'),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                search,
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(child: add),
                    const SizedBox(width: 10),
                    Expanded(child: reload),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: search),
              const SizedBox(width: 10),
              add,
              const SizedBox(width: 10),
              reload,
            ],
          );
        },
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.item,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final StoredFavorite item;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _FavoriteSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.accentDim(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(item.kind),
                  color: AppTheme.accent(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.text1(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        _FavoriteChip(label: item.kind.label),
                        if (item.password.isNotEmpty)
                          _FavoriteChip(label: '提取码 ${item.password}'),
                        if (item.source.isNotEmpty)
                          _FavoriteChip(label: item.source),
                        ...item.tags.map((String tag) {
                          return _FavoriteChip(label: tag);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              item.note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.text2(context),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.elevated(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              item.url,
              maxLines: 2,
              style: TextStyle(
                color: AppTheme.text3(context),
                fontFamily: 'Consolas',
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: const Text('复制'),
              ),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('编辑'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteEditorDialog extends StatefulWidget {
  const _FavoriteEditorDialog({required this.item});

  final StoredFavorite? item;

  @override
  State<_FavoriteEditorDialog> createState() => _FavoriteEditorDialogState();
}

class _FavoriteEditorDialogState extends State<_FavoriteEditorDialog> {
  late FavoriteKind _kind;
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _passwordController;
  late final TextEditingController _tagsController;
  late final TextEditingController _sourceController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final StoredFavorite? item = widget.item;
    _kind = item?.kind ?? FavoriteKind.magnet;
    _titleController = TextEditingController(text: item?.title ?? '');
    _urlController = TextEditingController(text: item?.url ?? '');
    _passwordController = TextEditingController(text: item?.password ?? '');
    _tagsController = TextEditingController(text: item?.tags.join(', ') ?? '');
    _sourceController = TextEditingController(text: item?.source ?? '');
    _noteController = TextEditingController(text: item?.note ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    _tagsController.dispose();
    _sourceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? '添加收藏' : '编辑收藏'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SegmentedButton<FavoriteKind>(
                showSelectedIcon: false,
                selected: <FavoriteKind>{_kind},
                segments: const <ButtonSegment<FavoriteKind>>[
                  ButtonSegment<FavoriteKind>(
                    value: FavoriteKind.magnet,
                    label: Text('磁力'),
                    icon: Icon(Icons.link_rounded),
                  ),
                  ButtonSegment<FavoriteKind>(
                    value: FavoriteKind.pan,
                    label: Text('网盘'),
                    icon: Icon(Icons.cloud_rounded),
                  ),
                  ButtonSegment<FavoriteKind>(
                    value: FavoriteKind.link,
                    label: Text('链接'),
                    icon: Icon(Icons.bookmark_rounded),
                  ),
                ],
                onSelectionChanged: (Set<FavoriteKind> values) {
                  setState(() => _kind = values.first);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(labelText: _urlLabel(_kind)),
              ),
              if (_kind == FavoriteKind.pan) ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: '提取码'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(labelText: '来源'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(labelText: '标签，用逗号分隔'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    final String url = _urlController.text.trim();
    if (!_validUrlFor(_kind, url)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(appSnack('${_urlLabel(_kind)}无效'));
      return;
    }
    final List<String> tags = _tagsController.text
        .split(RegExp(r'[,，]'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final StoredFavorite? item = widget.item;
    final StoredFavorite saved = item == null
        ? newStoredFavorite(
            kind: _kind,
            title: _titleController.text.trim(),
            url: url,
            password: _passwordController.text.trim(),
            tags: tags,
            note: _noteController.text.trim(),
            source: _sourceController.text.trim(),
          )
        : item.copyWith(
            kind: _kind,
            title: _titleController.text.trim(),
            url: url,
            password: _passwordController.text.trim(),
            tags: tags,
            note: _noteController.text.trim(),
            source: _sourceController.text.trim(),
          );
    Navigator.of(context).pop(saved);
  }
}

class _FavoriteEmptyState extends StatelessWidget {
  const _FavoriteEmptyState({required this.hasFilter});

  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return _FavoriteSurface(
      child: Column(
        children: <Widget>[
          Icon(
            hasFilter ? Icons.search_off_rounded : Icons.bookmark_add_outlined,
            color: AppTheme.text3(context),
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            hasFilter ? '没有匹配的收藏' : '还没有收藏',
            style: TextStyle(
              color: AppTheme.text1(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter ? '换个关键词试试。' : '可以收藏磁力、网盘链接或普通链接。',
            style: TextStyle(color: AppTheme.text3(context), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FavoriteSurface extends StatelessWidget {
  const _FavoriteSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border.all(color: AppTheme.border(context)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.isDark(context) ? 0.20 : 0.04,
            ),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.elevated(context),
        border: Border.all(color: AppTheme.border(context)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: AppTheme.text2(context), fontSize: 11),
      ),
    );
  }
}

extension on StoredFavorite {
  String get displayTitle {
    if (title.trim().isNotEmpty) {
      return title.trim();
    }
    if (kind == FavoriteKind.magnet) {
      final RegExpMatch? match = RegExp(
        r'btih:([a-zA-Z0-9]+)',
        caseSensitive: false,
      ).firstMatch(url);
      return match?.group(1) ?? url;
    }
    return url;
  }

  String get copyText {
    if (kind == FavoriteKind.pan && password.isNotEmpty) {
      return '$url\n提取码：$password';
    }
    return url;
  }
}

IconData _iconFor(FavoriteKind kind) {
  return switch (kind) {
    FavoriteKind.magnet => Icons.link_rounded,
    FavoriteKind.pan => Icons.cloud_rounded,
    FavoriteKind.link => Icons.bookmark_rounded,
  };
}

String _urlLabel(FavoriteKind kind) {
  return switch (kind) {
    FavoriteKind.magnet => 'Magnet',
    FavoriteKind.pan => '网盘链接',
    FavoriteKind.link => '链接',
  };
}

bool _validUrlFor(FavoriteKind kind, String url) {
  if (url.isEmpty) {
    return false;
  }
  if (kind == FavoriteKind.magnet) {
    return url.toLowerCase().startsWith('magnet:');
  }
  final Uri? uri = Uri.tryParse(url);
  return uri != null && uri.hasScheme && uri.host.isNotEmpty;
}
