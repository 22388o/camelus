import 'dart:async';
import 'dart:developer';

import 'package:camelus/atoms/long_button.dart';
import 'package:camelus/helpers/nprofile_helper.dart';
import 'package:camelus/routes/nostr/nostr_page/perspective_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:camelus/atoms/my_profile_picture.dart';
import 'package:camelus/components/tweet_card.dart';
import 'package:camelus/config/palette.dart';
import 'package:camelus/helpers/helpers.dart';
import 'package:camelus/models/tweet.dart';
import 'package:camelus/routes/nostr/profile/edit_profile_page.dart';
import 'package:camelus/routes/nostr/profile/edit_relays_page.dart';
import 'package:camelus/routes/nostr/profile/follower_page.dart';
import 'package:camelus/services/nostr/nostr_injector.dart';
import 'package:camelus/services/nostr/nostr_service.dart';
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends StatefulWidget {
  String pubkey;
  late String nProfile;
  late String nProfileHr;
  late String pubkeyBech32;
  late NostrService _nostrService;
  ProfilePage({Key? key, required this.pubkey}) : super(key: key) {
    NostrServiceInjector injector = NostrServiceInjector();
    _nostrService = injector.nostrService;

    nProfile = NprofileHelper().mapToBech32({
      "pubkey": pubkey,
      "relays": [],
    });
    nProfileHr = NprofileHelper().bech32toHr(nProfile);
    pubkeyBech32 = Helpers().encodeBech32(pubkey, "npub");
    repopulateNprofile();
  }

  repopulateNprofile() async {
    nProfile = await NprofileHelper().getNprofile(pubkey);
    nProfileHr = NprofileHelper().bech32toHr(nProfile);
    log("repopulated nprofile: $nProfileHr");
  }

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin, TraceableClientMixin {
  late ScrollController _scrollController;

  @override
  String get traceTitle => "profilePage";

  String nip05verified = "";
  String requestId = Helpers().getRandomString(14);

  List<Tweet> _myTweets = [];

  late StreamSubscription _nostrStream;

  bool loadTweetsLock = false;

  List<List> _myFollowing = [];
  bool _iamFollowing = false;
  bool _followTouched = false;

  String bannerUrl = "";

  var repliedToTmp = [];

  void _checkNip05(String nip05, String pubkey) async {
    if (nip05.isEmpty) return;
    if (nip05verified.isNotEmpty) return;
    try {
      var check = await widget._nostrService.checkNip05(nip05, pubkey);

      if (check["valid"] == true) {
        setState(() {
          nip05verified = check["nip05"];
        });
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  void checkIamFollowing() {
    _myFollowing =
        widget._nostrService.following[widget._nostrService.myKeys.publicKey] ??
            [];
    for (var i = 0; i < _myFollowing.length; i++) {
      if (_myFollowing[i][1] == widget.pubkey) {
        setState(() {
          _iamFollowing = true;
        });
      }
    }
  }

  void _follow() async {
    _followTouched = true;
    setState(() {
      _iamFollowing = true;
    });
    // edit _myFollowing
    _myFollowing.add(["p", widget.pubkey]);
    _saveFollowing();
  }

  void _unfollow() async {
    _followTouched = true;
    setState(() {
      _iamFollowing = false;
    });
    _myFollowing.removeWhere((element) => element[1] == widget.pubkey);
    _saveFollowing();
  }

  void _saveFollowing() async {
    if (!_followTouched) return;
    widget._nostrService.following[widget._nostrService.myKeys.publicKey] =
        _myFollowing;
    await widget._nostrService.writeEvent("", 3, _myFollowing);
  }

  Future<void> _copyToClipboard(String data) async {
    await Clipboard.setData(ClipboardData(text: data));
  }

  _getBannerImage() async {
    var metadata = await widget._nostrService.getUserMetadata(widget.pubkey);
    if (metadata["banner"] == null) return null;

    setState(() {
      bannerUrl = metadata["banner"];
    });

    return metadata["banner"];
  }

  _blockUser() async {
    // open dialog
    var result = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Block user"),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Are you sure you want to block this user?"),
                SizedBox(height: 20),
                Text("You will no longer see their posts."),
                SizedBox(height: 10),
                Text(
                    "This happens only locally if you login on another client you will see their posts again.")
              ],
            ),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: const Text("Block"),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        });
    if (!result) return;

    // add to blocked list
    await widget._nostrService.addToBlocklist(widget.pubkey);

    Navigator.pop(context);
  }

  _openLightningAddress(String lu06) async {
    final Uri lightningLaunchUri = Uri(
      scheme: 'lightning',
      path: lu06.toString(),
    );

    log("launching $lu06");
    launchUrl(lightningLaunchUri);
  }

  _launchPerspectiveFeed(String pubkey) async {
    log("launching perspective feed for $pubkey");

    // launch bottom sheet
    showModalBottomSheet(
        context: context,
        backgroundColor: Palette.background,
        barrierColor: Palette.black.withOpacity(0.8),
        builder: (context) {
          // ask for yes or no confirmation and return the result
          return Container(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    "perspective feed preview",
                    style: TextStyle(
                      color: Palette.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  const Text(
                    "Perspective is an experimental feature that allows you to see the feed of a specific user. My hope is that this will create an unbubble effect. Currently, this is only a proof of concept. It will break your home feed and clear the cache.\n\n The feed is also incomplete because its not using the gossip model for other users yet. \n\n If you tab yes, you signal you like this feature and want to see it in the future in a more polished form. If you tab no, you signal you don't like this feature and want to see it removed.",
                    style: TextStyle(
                      color: Palette.lightGray,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(
                    height: 50,
                  ),
                  Row(
                    children: [
                      // yes button

                      Expanded(
                        child: longButton(
                            name: "no",
                            onPressed: () {
                              _perspectiveFeedTrackAndLaunch(pubkey, false);
                            }),
                      ),

                      const SizedBox(
                        width: 20,
                      ),
                      Expanded(
                        child: longButton(
                            name: "yes",
                            onPressed: () {
                              _perspectiveFeedTrackAndLaunch(pubkey, true);
                            }),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 30,
                  ),
                ],
              ),
            ),
          );
        });
  }

  _perspectiveFeedTrackAndLaunch(String pubkey, bool feedback) async {
    MatomoTracker.instance.trackEvent(
      eventCategory: 'perspectiveFeed',
      action: 'perspectiveFeedLaunch',
      eventValue: feedback ? 1 : 0,
    );

    log("launching perspective feed for $pubkey, feedback: $feedback");
    // launch
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PerspectiveFeedPage(
          pubkey: pubkey,
        ),
      ),
    ).then((value) => {
          widget._nostrService.clearCache(),
          widget._nostrService.userFeedObj.feed = [],
        });
  }

  @override
  void initState() {
    super.initState();

    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // listen to nostr service
    _nostrStream =
        widget._nostrService.authorsFeedObj.authorsStream.listen((event) {
      setState(() {
        _myTweets = event[widget.pubkey] ?? [];
      });

      // todo make this better
      Future.delayed(const Duration(seconds: 5), () {
        loadTweetsLock = false;
      });
    });

    // subscribe to user's tweets
    widget._nostrService.requestAuthors(
        authors: [widget.pubkey], requestId: requestId, limit: 10, until: now);

    _scrollController = ScrollController();
    _scrollController.addListener(() {
      setState(() {});
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 100) {
        if (loadTweetsLock) return;
        loadTweetsLock = true;
        // load more tweets
        log("load more tweets");
        widget._nostrService.requestAuthors(
            authors: [widget.pubkey],
            requestId: requestId,
            limit: 10,
            until: _myTweets.last.tweetedAt);
      }
    });

    checkIamFollowing();
    _getBannerImage();
  }

  @override
  void dispose() {
    _scrollController.dispose();

    _nostrStream.cancel();

    // cancel subscription
    widget._nostrService.closeSubscription("authors-$requestId");

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                expandedHeight: 150,
                //toolbarHeight: 10,
                backgroundColor: Palette.background,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                    background: bannerUrl.isNotEmpty
                        ? Image.network(
                            bannerUrl,
                            fit: BoxFit.cover,
                          )
                        : Image.asset(
                            'assets/images/default_header.jpg',
                            fit: BoxFit.cover,
                          )),

                actions: [
                  PopupMenuButton<String>(
                    tooltip: "More",
                    onSelected: (e) => {
                      //log(e),
                      // toast
                      if (e == "block") _blockUser()
                    },
                    itemBuilder: (BuildContext context) {
                      return {'block'}.map((String choice) {
                        return PopupMenuItem<String>(
                          value: choice,
                          child: Text(choice),
                        );
                      }).toList();
                    },
                  ),
                ],
                // rounded back button
                leading: Container(
                  margin: const EdgeInsets.all(0),
                  padding: const EdgeInsets.only(top: 10, right: 0, left: 0),
                  child: ButtonTheme(
                    minWidth: 10,
                    height: 1,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.all(0),
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Palette.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(0),
                  child: Container(),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate(
                  [
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.pubkey !=
                            widget._nostrService.myKeys.publicKey)
                          SizedBox(
                            width: 35,
                            height: 35,
                            child: ElevatedButton(
                              onPressed: () {
                                _launchPerspectiveFeed(widget.pubkey);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Palette.background,
                                padding: const EdgeInsets.all(0),
                                enableFeedback: true,
                                shape: const CircleBorder(
                                    side: BorderSide(
                                        color: Palette.white, width: 1)),
                              ),
                              child: SvgPicture.asset(
                                "assets/icons/eye.svg",
                                height: 25,
                                color: Palette.white,
                              ),
                            ),
                          ),

                        // round message button with icon and white border
                        FutureBuilder<Map>(
                            future: widget._nostrService
                                .getUserMetadata(widget.pubkey),
                            builder: (BuildContext context,
                                AsyncSnapshot<Map> snapshot) {
                              String lud06 = "";
                              String lud16 = "";

                              if (snapshot.hasData) {
                                lud06 = snapshot.data?["lud06"] ?? "";
                                lud16 = snapshot.data?["lud16"] ?? "";
                              }

                              if (lud06.isNotEmpty || lud16.isNotEmpty) {
                                return Container(
                                  margin: const EdgeInsets.only(
                                      top: 0, right: 0, left: 0),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (lud06.isNotEmpty) {
                                        _openLightningAddress(lud06);
                                      } else if (lud16.isNotEmpty) {
                                        _openLightningAddress(lud16);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Palette.background,
                                      padding: const EdgeInsets.all(0),
                                      shape: const CircleBorder(
                                          side: BorderSide(
                                              color: Palette.white, width: 1)),
                                    ),
                                    child: SvgPicture.asset(
                                      "assets/icons/lightning-fill.svg",
                                      height: 25,
                                      color: Palette.white,
                                    ),
                                  ),
                                );
                              } else {
                                return Container();
                              }
                            }),

                        // follow button black with white border

                        if (widget.pubkey !=
                                widget._nostrService.myKeys.publicKey &&
                            !_iamFollowing)
                          Container(
                            margin: const EdgeInsets.only(top: 0, right: 10),
                            child: ElevatedButton(
                              onPressed: () {
                                _follow();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Palette.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: const BorderSide(
                                      color: Palette.black, width: 1),
                                ),
                              ),
                              child: const Text(
                                'Follow',
                                style: TextStyle(
                                  color: Palette.black,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),

                        // unfollow button white with black border
                        if (widget.pubkey !=
                                widget._nostrService.myKeys.publicKey &&
                            _iamFollowing)
                          Container(
                            margin: const EdgeInsets.only(top: 0, right: 10),
                            child: ElevatedButton(
                              onPressed: () {
                                _unfollow();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Palette.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: const BorderSide(
                                      color: Palette.white, width: 1),
                                ),
                              ),
                              child: const Text(
                                'Unfollow',
                                style: TextStyle(
                                  color: Palette.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),

                        // edit button
                        if (widget.pubkey ==
                            widget._nostrService.myKeys.publicKey)
                          Container(
                            margin: const EdgeInsets.only(top: 0, right: 10),
                            child: ElevatedButton(
                              onPressed: () {
                                _saveFollowing();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditProfilePage(),
                                  ),
                                ).then((value) => {
                                      widget._nostrService
                                          .getUserMetadata(widget.pubkey),
                                      _getBannerImage(),
                                      setState(() {
                                        // refresh
                                      })
                                    });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Palette.background,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: const BorderSide(
                                      color: Palette.white, width: 1),
                                ),
                              ),
                              child: const Text(
                                'Edit',
                                style: TextStyle(
                                  color: Palette.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // move up the profile info by 110
                    Container(
                      transform: Matrix4.translationValues(0.0, -10.0, 0.0),
                      child: FutureBuilder<Map>(
                        future:
                            widget._nostrService.getUserMetadata(widget.pubkey),
                        builder: (BuildContext context,
                            AsyncSnapshot<Map> snapshot) {
                          var name = "";
                          var nip05 = "";
                          var picture = "";
                          var about = "";

                          if (snapshot.hasData) {
                            name = snapshot.data?["name"] ?? "";
                            nip05 = snapshot.data?["nip05"] ?? "";
                            picture = snapshot.data?["picture"] ?? "";
                            about = snapshot.data?["about"] ?? "";

                            _checkNip05(nip05, widget.pubkey);
                          } else if (snapshot.hasError) {
                            name = "error";
                            nip05 = "error";
                            picture = "";
                            about = "error";
                          } else {
                            // loading
                            name = "loading";
                            nip05 = "loading";
                            picture = "";
                            about = "loading";
                          }

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              //profile name
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    margin:
                                        const EdgeInsets.only(top: 0, left: 20),
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        color: Palette.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (nip05verified.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(
                                          top: 0, left: 5),
                                      child: const Icon(
                                        Icons.verified,
                                        color: Palette.white,
                                        size: 23,
                                      ),
                                    ),
                                ],
                              ),
                              // handle
                              Container(
                                margin: const EdgeInsets.only(top: 0, left: 20),
                                child: Row(
                                  children: [
                                    if (nip05verified.isNotEmpty)
                                      Text(
                                        // if name equals name@example.com then hide the name and show only the domain
                                        name.contains("@")
                                            ? name.split("@")[1]
                                            : nip05verified.split("@")[1],

                                        style: const TextStyle(
                                          color: Palette.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    // verified icon
                                  ],
                                ),
                              ),
                              // pub key in short form (first 10 chars + ... + last 10 chars) + copy button with icon
                              Container(
                                margin: const EdgeInsets.only(top: 0, left: 20),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        _copyToClipboard(widget.pubkeyBech32);
                                      },
                                      child: Container(
                                        transform: Matrix4.translationValues(
                                            -12.0, 0.0, 0.0),
                                        // rounded
                                        padding: const EdgeInsets.only(
                                            top: 5,
                                            bottom: 5,
                                            left: 12,
                                            right: 12),
                                        decoration: const BoxDecoration(
                                          color: Palette.extraDarkGray,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(20),
                                          ),
                                        ),
                                        child: Text(
                                          '${widget.pubkeyBech32.substring(0, 10)}...${widget.pubkeyBech32.substring(widget.pubkeyBech32.length - 10)}',
                                          style: const TextStyle(
                                            color: Palette.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'copy nprofile',
                                      onPressed: () {
                                        _copyToClipboard(widget.nProfile);
                                      },
                                      icon: const Icon(
                                        Icons.copy,
                                        color: Palette.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              // bio
                              Container(
                                margin: const EdgeInsets.only(top: 0, left: 20),
                                child: SelectableText(
                                  about,
                                  style: const TextStyle(
                                    color: Palette.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                            ],
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people,
                                color: Palette.white, size: 17),
                            const SizedBox(width: 5),
                            FutureBuilder<List<List<dynamic>>>(
                                future: widget._nostrService
                                    .getUserContacts(widget.pubkey),
                                builder: (BuildContext context,
                                    AsyncSnapshot<List<List<dynamic>>>
                                        snapshot) {
                                  var contactsCountString = "";

                                  if (snapshot.hasData) {
                                    var count = snapshot.data?.length;
                                    contactsCountString = "$count following";
                                  } else if (snapshot.hasError) {
                                    contactsCountString = "n.a. following";
                                  } else {
                                    // loading
                                    contactsCountString = "... following";
                                  }

                                  return GestureDetector(
                                    onTap: () {
                                      if (snapshot.data!.isEmpty) {
                                        return;
                                      }
                                      _saveFollowing();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FollowerPage(
                                            contacts: snapshot.data ?? [],
                                            title: "Following",
                                          ),
                                        ),
                                      ).then((value) => setState(() {}));
                                    },
                                    child: Text(
                                      contactsCountString,
                                      style: const TextStyle(
                                        color: Palette.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  );
                                }),
                          ],
                        ),
                        const Row(
                          children: [
                            Icon(Icons.follow_the_signs,
                                color: Palette.white, size: 17),
                            SizedBox(width: 5),
                            Text("n.a. followers",
                                style: TextStyle(
                                  color: Palette.white,
                                  fontSize: 14,
                                )),
                          ],
                        ),
                        GestureDetector(
                          onTap: () {
                            if (widget.pubkey ==
                                widget._nostrService.myKeys.publicKey) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditRelaysPage(),
                                ),
                              ).then((value) => setState(() {}));
                            }
                          },
                          child: Row(
                            children: [
                              const Icon(Icons.connect_without_contact,
                                  color: Palette.white, size: 17),
                              const SizedBox(width: 5),
                              if (widget.pubkey ==
                                  widget._nostrService.myKeys.publicKey)
                                Text(
                                  "${widget._nostrService.relays.manualRelays.length} relays",
                                  style: const TextStyle(
                                    color: Palette.white,
                                    fontSize: 14,
                                  ),
                                ),
                              if (widget.pubkey !=
                                  widget._nostrService.myKeys.publicKey)
                                const Text(
                                  "n.a. relays",
                                  style: TextStyle(
                                    color: Palette.white,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return TweetCard(
                      tweet: _myTweets[index],
                    );
                  },
                  childCount: _myTweets.length,
                ),
              ),
            ],
          ),
          _profileImage(_scrollController, widget),
          SafeArea(
            child: SizedBox(
              height: 55,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // fade in the text when the profile image is scrolled out of view
                  AnimatedOpacity(
                    opacity: _scrollController.hasClients &&
                            _scrollController.offset > 100
                        ? 1.0
                        : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: FutureBuilder<Map>(
                        future:
                            widget._nostrService.getUserMetadata(widget.pubkey),
                        builder: (BuildContext context,
                            AsyncSnapshot<Map> snapshot) {
                          var name = "";

                          if (snapshot.hasData) {
                            name = snapshot.data?["name"] ??
                                '${widget.nProfile.substring(0, 10)}...${widget.nProfile.substring(widget.pubkey.length - 10)}';
                          } else if (snapshot.hasError) {
                            name = "error";
                          } else {
                            // loading
                            name = "loading";
                          }

                          return Text(
                            name,
                            style: const TextStyle(
                              color: Palette.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

Widget _profileImage(ScrollController sController, widget) {
  const double defaultMargin = 125;
  const double defaultStart = 125;
  const double defaultEnd = defaultStart / 2;

  double top = defaultMargin;
  double scale = 1.0;

  if (sController.hasClients) {
    double offset = sController.offset;
    top -= offset;

    if (offset < defaultMargin - defaultStart) {
      scale = 1.0;
    } else if (offset < defaultStart - defaultEnd) {
      scale = (defaultMargin - defaultEnd - offset) / defaultEnd;
    } else {
      scale = 0.0;
    }
  }

  // open image in full screen with dialog and zoom
  void openImage(ImageProvider image, BuildContext context) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            clipBehavior: Clip.antiAliasWithSaveLayer,
            insetPadding: const EdgeInsets.all(5),
            child: PhotoView(
              minScale: PhotoViewComputedScale.contained * 1,
              onTapUp: (context, details, controllerValue) {
                Navigator.pop(context);
              },
              tightMode: true,
              imageProvider: image,
            ),
          );
        });
  }

  return Positioned(
    top: top,
    left: 0,
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(scale),
      child: Container(
        margin: const EdgeInsets.only(top: 0, left: 20),
        height: 100,
        width: 100,
        decoration: BoxDecoration(
          border: Border.all(color: Palette.background, width: 3),
          shape: BoxShape.circle,
        ),
        child: FutureBuilder<Map>(
            future: widget._nostrService.getUserMetadata(widget.pubkey),
            builder: (BuildContext context, AsyncSnapshot<Map> snapshot) {
              var picture = "";

              if (snapshot.hasData) {
                picture = snapshot.data?["picture"] ??
                    "https://avatars.dicebear.com/api/personas/${widget.pubkey}.svg";
              } else if (snapshot.hasError) {
                picture =
                    "https://avatars.dicebear.com/api/personas/${widget.pubkey}.svg";
              } else {
                // loading
                picture =
                    "https://avatars.dicebear.com/api/personas/${widget.pubkey}.svg";
              }
              return GestureDetector(
                  onTap: (() {
                    openImage(NetworkImage(picture), context);
                  }),
                  child: myProfilePicture(picture, widget.pubkey));
            }),
      ),
    ),
  );
}
