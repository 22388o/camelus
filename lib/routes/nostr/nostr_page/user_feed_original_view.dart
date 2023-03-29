import 'dart:async';
import 'dart:developer';

import 'package:camelus/atoms/spinner_center.dart';
import 'package:camelus/components/tweet_card.dart';
import 'package:camelus/config/palette.dart';
import 'package:camelus/models/tweet.dart';
import 'package:camelus/physics/position_retained_scroll_physics.dart';
import 'package:camelus/scroll_controller/retainable_scroll_controller.dart';
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

  bool _newPostsAvailable = false;

  final GlobalKey _listKey = GlobalKey<AnimatedListState>();

  List<Tweet> _displayList = [];

  late List<String> _followingPubkeys;

  //late final ScrollController _scrollControllerFeed = ScrollController();
  late final RetainableScrollController _scrollControllerFeed =
      RetainableScrollController();

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
    _displayList.sort((a, b) => a.tweetedAt.compareTo(b.tweetedAt));

    // if empty, just add all
    if (_displayList.isEmpty) {
      setState(() {
        _displayList = List.from(tweets);
      });
      return;
    }

    // calculate new tweets
    List<Tweet> newTweets = [];
    List<Tweet> findIndexTweets = [];
    for (var t in tweets) {
      if (!_displayList.contains(t)) {
        if (t.tweetedAt > _displayList.last.tweetedAt) {
          newTweets.add(t);
        } else {
          findIndexTweets.add(t);
        }
      }
    }

    // insert tweet at correct position
    for (var t in findIndexTweets) {
      int index =
          _displayList.indexWhere((element) => element.tweetedAt > t.tweetedAt);
      if (index == -1) {
        index = _displayList.length;
      }
      _displayList.insert(index, t);
    }

    //for (var t in findIndexTweets) {
    //  int index =
    //      _displayList.indexWhere((element) => element.tweetedAt > t.tweetedAt);
    //  if (index == -1) {
    //    index = _displayList.length;
    //  }
    //  _displayList.insert(index, t);
    //}

    setState(() {
      //todo: keep scroll position
      //_displayList = List.from(tweets);

      if (newTweets.isNotEmpty) {
        _newPostsAvailable = true;
        //_displayList.insertAll(0, newTweets);
        _displayList.addAll(newTweets);
      }

      if (!_isLoading) {
        _scrollControllerFeed.retainOffset();
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
        until: _displayList.first.tweetedAt,
        includeComments: true);

    // lock croll and keep position

    _scrollControllerFeed.jumpTo(0);
  }

  void _setupScrollListener() {
    _scrollControllerFeed.addListener(() {
      if (_scrollControllerFeed.position.pixels ==
          _scrollControllerFeed.position.maxScrollExtent) {
        log("reached top");

        //_userFeedLoadMore();
      }

      if (_scrollControllerFeed.position.pixels == 0) {
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

    return Stack(
      children: [
        RefreshIndicator(
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
            slivers: [
              SliverList(
                //key: _leadingKey,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return TweetCard(
                      tweet: _displayList[index],
                    );
                  },
                  childCount: _displayList.length + 1,
                ),
              ),
              SliverList(
                // key: _centerKey,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return TweetCard(
                      tweet: _displayList[index],
                    );
                  },
                  childCount: _displayList.length + 1,
                ),
              ),
              SliverList(
                // key: _trailingKey,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return TweetCard(
                      tweet: _displayList[index],
                    );
                  },
                  childCount: _displayList.length + 1,
                ),
              ),
            ],
          ),
        ),

        // if it is top
        if (_newPostsAvailable)
          Positioned(
              top: 20,
              width: MediaQuery.of(context).size.width,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Container(
                      width: 120,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Palette.primary,
                      ),
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _newPostsAvailable = false;
                          });
                          // animate to last
                          _scrollControllerFeed.animateTo(
                              _scrollControllerFeed.position.maxScrollExtent +
                                  100,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut);
                        },
                        child: const Text(
                          "new posts",
                          style: TextStyle(color: Palette.white),
                        ),
                      ))
                ],
              )),
      ],
    );
  }
}
