import 'dart:async';
import 'dart:developer';

import 'package:camelus/atoms/spinner_center.dart';
import 'package:camelus/components/tweet_card.dart';
import 'package:camelus/config/palette.dart';
import 'package:camelus/models/tweet.dart';
import 'package:camelus/services/nostr/nostr_injector.dart';
import 'package:camelus/services/nostr/nostr_service.dart';
import 'package:flutter/material.dart';

class UserFeedOriginalView extends StatefulWidget {
  late NostrService _nostrService;
  late String pubkey;

  UserFeedOriginalView({Key? key, required this.pubkey}) : super(key: key) {
    NostrServiceInjector injector = NostrServiceInjector();
    _nostrService = injector.nostrService;
  }

  @override
  State<UserFeedOriginalView> createState() => _UserFeedOriginalViewState();
}

class _UserFeedOriginalViewState extends State<UserFeedOriginalView> {
  // user feed
  late StreamSubscription userFeedSubscription;
  bool isUserFeedSubscribed = false;
  static String userFeedFreshId = "fresh";
  static String userFeedTimelineFetchId = "timeline";

  bool _isLoading = true;

  final GlobalKey _listKey = GlobalKey<AnimatedListState>();

  List<Tweet> _displayList = [];

  late List<String> _followingPubkeys;

  late final ScrollController _scrollControllerFeed = ScrollController();

  /// only for initial load
  void _initUserFeed() async {
    //wait for connection
    bool connection = await widget._nostrService.isNostrServiceConnected;
    if (!connection) {
      log("no connection to nostr service");
      return;
    }

    // check mounted
    if (!mounted) {
      log("not mounted");
      return;
    }

    _subscribeToUserFeed();
    setState(() {
      isUserFeedSubscribed = true;
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _subscribeToUserFeed() async {
    if (isUserFeedSubscribed) return;
    log("subscribed to user feed called");

    /// map with pubkey as identifier, second list [0] is p, [1] is pubkey, [2] is the relay url
    var following = await widget._nostrService.getUserContacts(widget.pubkey);

    // extract public keys
    _followingPubkeys = [];
    for (var f in following) {
      _followingPubkeys.add(f[1]);
    }

    if (_followingPubkeys.isEmpty) {
      log("!!! no following users found !!!");
    }

    // add own pubkey
    _followingPubkeys.add(widget.pubkey);

    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    int latestTweet = now - 86400; // -1 day
    if (_displayList.isNotEmpty) {
      latestTweet = _displayList.first.tweetedAt;
    }

    widget._nostrService.requestUserFeed(
        users: _followingPubkeys,
        requestId: userFeedFreshId,
        limit: 50,
        since: latestTweet, //since latest tweet
        includeComments: false);

    setState(() {
      isUserFeedSubscribed = true;
    });
  }

  void _unsubscribeFromUserFeed() {
    if (!isUserFeedSubscribed) return;
    log("nostr:page unsubscribed from user feed called");

    widget._nostrService.closeSubscription("ufeed-$userFeedFreshId");
    if (userFeedTimelineFetchId.isNotEmpty) {
      widget._nostrService.closeSubscription("ufeed-$userFeedTimelineFetchId");
    }
    setState(() {
      isUserFeedSubscribed = false;
    });
  }

  /// listener attached from the NostrService
  _onUserFeedReceived(List<Tweet> tweets) {
    // sort by tweetedAt
    //_displayList.sort((a, b) => b.tweetedAt.compareTo(a.tweetedAt));

    setState(() {
      //todo: keep scroll position
      _displayList = List.from(tweets);

      //_displayList.insertAll(0, tweets);
      //_displayList.insert(0, tweets.first);
      try {
        //_scrollControllerFeed
        //    .jumpTo(_scrollControllerFeed.position.maxScrollExtent);
        // keep scroll position

      } catch (e) {
        log("scroll controller not initialized yet");
      }
    });
  }

  /// timeline scroll request more tweets
  void _userFeedLoadMore() async {
    log("load more called");

    if (_followingPubkeys.isEmpty) {
      log("!!! no following users found !!!");
      return;
    }

    widget._nostrService.requestUserFeed(
        users: _followingPubkeys,
        requestId: userFeedTimelineFetchId,
        limit: 20,
        until: _displayList.last.tweetedAt,
        includeComments: true);
  }

  void _setupScrollListener() {
    _scrollControllerFeed.addListener(() {
      //log("scrolling ${_scrollControllerUserFeedOriginal.position.pixels} -- ${_scrollControllerUserFeedOriginal.position.maxScrollExtent}");
      if (_scrollControllerFeed.position.pixels ==
          _scrollControllerFeed.position.maxScrollExtent) {
        //log("reached bottom");

        _userFeedLoadMore();
      }
    });
  }

  @override
  void initState() {
    // todo:
    log(widget.pubkey + "##################");

    _initUserFeed();
    _setupScrollListener();

    userFeedSubscription =
        widget._nostrService.userFeedObj.userFeedStream.listen((event) {
      _onUserFeedReceived(event);
    });

    super.initState();
  }

  @override
  void dispose() {
    // todo:
    // cancel subscription
    try {
      userFeedSubscription.cancel();
    } catch (e) {}

    _scrollControllerFeed.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_displayList.isEmpty && _isLoading) {
      return spinnerCenter();
    }
    if (_displayList.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              "no tweets yet",
              style: TextStyle(fontSize: 25, color: Palette.white),
            ),
            SizedBox(height: 20),
            Text(
              "follow people to see their tweets (global feed)",
              style: TextStyle(fontSize: 15, color: Palette.white),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Palette.primary,
      backgroundColor: Palette.extraDarkGray,
      onRefresh: () {
        // todo fix this hack (should auto update)
        isUserFeedSubscribed = false;
        _subscribeToUserFeed();
        return Future.delayed(const Duration(milliseconds: 150));
      },
      child: CustomScrollView(
        controller: _scrollControllerFeed,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverList(
            key: _listKey,
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                return TweetCard(
                  tweet: _displayList[index],
                );
              },
              childCount: _displayList.length,
            ),
          ),
        ],
      ),
    );
  }
}
