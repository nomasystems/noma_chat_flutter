import 'package:flutter/foundation.dart';
import '../../core/pagination.dart';
import '../../core/result.dart';
import '../../models/message.dart';

/// Controller for searching messages within a room, with loading state and pagination.
class MessageSearchController extends ChangeNotifier {
  MessageSearchController({required this.searchFn});

  final Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> Function(
    String query,
    String roomId, {
    ChatPaginationParams? pagination,
  })
  searchFn;

  String _query = '';
  String _roomId = '';
  List<ChatMessage> _results = [];
  bool _isLoading = false;
  bool _hasMore = false;

  String get query => _query;
  List<ChatMessage> get results => List.unmodifiable(_results);
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> search(String query, String roomId) async {
    _query = query;
    _roomId = roomId;
    if (query.isEmpty) {
      _results = [];
      _isLoading = false;
      _hasMore = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    final result = await searchFn(query, roomId);

    _isLoading = false;
    if (result.isSuccess) {
      final data = result.dataOrThrow;
      _results = List.from(data.items);
      _hasMore = data.hasMore;
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading || _query.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    final result = await searchFn(
      _query,
      _roomId,
      pagination: ChatPaginationParams(offset: _results.length),
    );

    _isLoading = false;
    if (result.isSuccess) {
      final data = result.dataOrThrow;
      _results = [..._results, ...data.items];
      _hasMore = data.hasMore;
    }
    notifyListeners();
  }

  void clear() {
    _query = '';
    _roomId = '';
    _results = [];
    _isLoading = false;
    _hasMore = false;
    notifyListeners();
  }
}
