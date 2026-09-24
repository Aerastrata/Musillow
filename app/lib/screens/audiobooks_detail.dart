import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/abs_client.dart';
import '../services/abs_progress.dart';
import '../services/abs_state.dart';
import '../services/player_service.dart';
import '../theme.dart';
import 'now_playing_screen.dart';

/// Network image (book cover / author photo) with a placeholder.
class _NetImg extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final bool circle;
  const _NetImg(this.url, {this.size = 52, this.radius = 10, this.circle = false});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size : radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _ph(),
                loadingBuilder: (c, child, p) => p == null ? child : _ph(),
              )
            : _ph(),
      ),
    );
  }

  Widget _ph() => Container(
    color: AppColors.surfaceAlt,
    child: const Icon(
      SolarIconsBold.headphonesRoundSound,
      color: AppColors.textFaint,
      size: 22,
    ),
  );
}

/// Load an Audiobookshelf book and start it at the saved position.
///
/// Public because Home's "Continue listening" row resumes books directly
/// rather than bouncing through the audiobook list.
Future<void> playBook(BuildContext context, String itemId) async {
  final client = absState.client;
  if (client == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final tracks = await client.bookTracks(itemId);
    if (tracks.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No audio in this book.')),
      );
      return;
    }
    // Cumulative start time of each file, and the book's total duration.
    final offsets = <double>[];
    var acc = 0.0;
    for (final t in tracks) {
      offsets.add(acc);
      acc += (t.durationSeconds ?? 0).toDouble();
    }
    final total = acc;

    // Resume from the saved ABS position (unless finished/unstarted).
    final resumeAt = await client.progressSeconds(itemId);
    var startIndex = 0;
    var into = 0.0;
    if (resumeAt > 0 && (total == 0 || resumeAt < total)) {
      for (var i = 0; i < tracks.length; i++) {
        final end = (i + 1 < offsets.length) ? offsets[i + 1] : double.infinity;
        if (resumeAt < end) {
          startIndex = i;
          into = resumeAt - offsets[i];
          break;
        }
      }
    }

    playerService.playQueue(
      tracks,
      startIndex,
      reporter: AbsProgressReporter(
        client: client,
        itemId: itemId,
        offsets: offsets,
        total: total,
      ),
      initialPosition: Duration(seconds: into.clamp(0, double.maxFinite).round()),
    );
    navigator.push(NowPlayingScreen.route());
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
  }
}

Widget _scaffold(BuildContext context, String title, Widget child) => Scaffold(
  appBar: AppBar(
    title: Text(title),
    titleTextStyle: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w800,
    ),
    leading: IconButton(
      icon: const Icon(SolarIconsOutline.altArrowLeft),
      onPressed: () => Navigator.of(context).maybePop(),
    ),
  ),
  body: child,
);

/// A searchable grid of audiobooks; tapping a book plays it.
class BooksGridScreen extends StatelessWidget {
  final String title;
  final Future<List<Audiobook>> future;
  const BooksGridScreen({super.key, required this.title, required this.future});

  @override
  Widget build(BuildContext context) {
    return _scaffold(
      context,
      title,
      _BooksGridBody(title: title, future: future),
    );
  }
}

/// The search field + grid body (no Scaffold), reusable inside other screens.
class _BooksGridBody extends StatefulWidget {
  final String title;
  final Future<List<Audiobook>> future;
  const _BooksGridBody({required this.title, required this.future});

  @override
  State<_BooksGridBody> createState() => _BooksGridBodyState();
}

class _BooksGridBodyState extends State<_BooksGridBody> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: AppColors.textPrimary),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search ${widget.title}',
                hintStyle: const TextStyle(color: AppColors.textFaint),
                prefixIcon: const Icon(
                  SolarIconsOutline.magnifier,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.all(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Audiobook>>(
              future: widget.future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                if (snap.hasError) return _msg("Couldn't load.");
                final all = snap.data ?? const [];
                if (all.isEmpty) return _msg('Nothing here yet.');
                final books = _q.isEmpty
                    ? all
                    : all
                          .where(
                            (b) =>
                                b.title.toLowerCase().contains(_q) ||
                                b.author.toLowerCase().contains(_q),
                          )
                          .toList();
                if (books.isEmpty) return _msg('No matches for "$_q".');
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.62,
                      ),
                  itemCount: books.length,
                  itemBuilder: (context, i) => _BookCard(book: books[i]),
                );
              },
            ),
          ),
        ],
      );
  }

  Widget _msg(String t) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textFaint),
      ),
    ),
  );
}

class _BookCard extends StatelessWidget {
  final Audiobook book;
  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => playBook(context, book.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) =>
                _NetImg(book.coverUrl, size: c.maxWidth, radius: 12),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// The Audio Books tile: a Series strip on top, then all books.
class AudioBooksScreen extends StatelessWidget {
  const AudioBooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = absState.client!;
    final libId = absState.libraryId!;
    return _scaffold(
      context,
      'Audio Books',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SeriesStrip(future: client.series(libId)),
          Expanded(
            child: _BooksGridBody(
              title: 'Audio Books',
              future: client.books(libId),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal strip of series; tap opens that series' books.
class _SeriesStrip extends StatelessWidget {
  final Future<List<AbsSeries>> future;
  const _SeriesStrip({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AbsSeries>>(
      future: future,
      builder: (context, snap) {
        final series = snap.data ?? const [];
        if (series.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Series',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: series.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final s = series[i];
                  return ActionChip(
                    label: Text(s.name),
                    backgroundColor: AppColors.surfaceAlt,
                    labelStyle: const TextStyle(color: AppColors.textPrimary),
                    side: const BorderSide(color: AppColors.border),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BooksGridScreen(
                          title: s.name,
                          future: Future.value(s.books),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The Authors tile → list of ABS authors → their books.
class AbsAuthorsScreen extends StatefulWidget {
  const AbsAuthorsScreen({super.key});

  @override
  State<AbsAuthorsScreen> createState() => _AbsAuthorsScreenState();
}

class _AbsAuthorsScreenState extends State<AbsAuthorsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final client = absState.client!;
    final libId = absState.libraryId!;
    return _scaffold(
      context,
      'Authors',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: const TextStyle(color: AppColors.textPrimary),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search Authors',
                hintStyle: const TextStyle(color: AppColors.textFaint),
                prefixIcon: const Icon(
                  SolarIconsOutline.magnifier,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.all(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AbsAuthor>>(
              future: client.authors(libId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final all = snap.data ?? const [];
                final authors = _q.isEmpty
                    ? all
                    : all
                          .where((a) => a.name.toLowerCase().contains(_q))
                          .toList();
                if (authors.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No authors found.',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 140),
                  itemCount: authors.length,
                  itemBuilder: (context, i) {
                    final a = authors[i];
                    return ListTile(
                      leading: _NetImg(a.coverUrl, circle: true),
                      title: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: a.numBooks != null
                          ? Text(
                              '${a.numBooks} books',
                              style: const TextStyle(color: AppColors.textMuted),
                            )
                          : null,
                      trailing: const Icon(
                        SolarIconsOutline.altArrowRight,
                        color: AppColors.textFaint,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BooksGridScreen(
                            title: a.name,
                            future: client.authorBooks(a.id),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
