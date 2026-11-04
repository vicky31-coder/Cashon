import 'package:budget/colors.dart';
import 'package:budget/database/generatePreviewData.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/addBudgetPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/languageMap.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/currencyPicker.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/linearGradientFadedEdges.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;
import 'package:budget/functions.dart';
import 'package:budget/database/initializeDefaultDatabase.dart';
import 'package:budget/pages/addTransactionPage.dart' show HorizontalBreak;
import 'package:budget/struct/pocketbaseService.dart';
import 'package:budget/struct/pocketbaseSync.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';

import 'package:budget/widgets/pageIndicator.dart';

class OnBoardingPage extends StatelessWidget {
  const OnBoardingPage({
    Key? key,
    this.popNavigationWhenDone = false,
    this.showPreviewDemoButton = true,
  }) : super(key: key);

  final bool popNavigationWhenDone;
  final bool showPreviewDemoButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: true,
        body: OnBoardingPageBody(
            popNavigationWhenDone: popNavigationWhenDone,
            showPreviewDemoButton: showPreviewDemoButton));
  }
}

class OnBoardingPageBody extends StatefulWidget {
  const OnBoardingPageBody({
    Key? key,
    this.popNavigationWhenDone = false,
    this.showPreviewDemoButton = true,
  }) : super(key: key);
  final bool popNavigationWhenDone;
  final bool showPreviewDemoButton;

  @override
  State<OnBoardingPageBody> createState() => OnBoardingPageBodyState();
}

class OnBoardingPageBodyState extends State<OnBoardingPageBody> {
  final PageController controller = PageController();

  double? selectedAmount;
  int selectedPeriodLength = 1;
  DateTime selectedStartDate = DateTime.now().firstDayOfMonth();
  DateTime? selectedEndDate;
  String selectedRecurrence = "Monthly";
  bool selectedIncludeIncome = false;

  bool showImage = false;
  final Image imageLanding1 = Image(
    image: AssetImage("assets/landing/Graph.png"),
  );
  final Image imageLanding2 = Image(
    image: AssetImage("assets/landing/BankOrPig.png"),
  );
  final Image imageLanding3 = Image(
    image: AssetImage("assets/landing/PigBank.png"),
  );

  @override
  void didChangeDependencies() {
    precacheImage(imageLanding1.image, context);
    precacheImage(imageLanding2.image, context);
    precacheImage(imageLanding3.image, context);
    super.didChangeDependencies();
  }

  nextNavigation({bool generatePreview = false}) async {
    if (selectedAmount != null && selectedAmount != 0) {
      int order = await database.getAmountOfBudgets();
      await database.createOrUpdateBudget(
        insert: true,
        Budget(
          budgetPk: "-1",
          name: "default-budget-name".tr(),
          amount: selectedAmount ?? 0,
          startDate: selectedStartDate,
          endDate: selectedEndDate ?? DateTime.now(),
          addedTransactionsOnly: false,
          periodLength: selectedPeriodLength,
          dateCreated: DateTime.now(),
          pinned: true,
          order: order,
          walletFk: "0",
          reoccurrence: mapRecurrence(selectedRecurrence),
          isAbsoluteSpendingLimit: false,
          budgetTransactionFilters: [
            ...(selectedIncludeIncome == false
                ? [BudgetTransactionFilters.defaultBudgetTransactionFilters]
                : [
                    BudgetTransactionFilters.includeIncome,
                    BudgetTransactionFilters.addedToOtherBudget,
                    BudgetTransactionFilters.addedToObjective,
                  ])
          ],
          income: false,
          archived: false,
        ),
      );
    }
    if (generatePreview) {
      openLoadingPopup(context);
      await generatePreviewData();
      popRoute(context);
    }
    if (widget.popNavigationWhenDone) {
      popRoute(context);
    } else {
      updateSettings("hasOnboarded", true,
          pagesNeedingRefresh: [], updateGlobalState: true);
    }
  }

  FocusNode _focusNode = FocusNode();
  late FocusAttachment _focusAttachment;

  bool _showLoginForm = false;
  bool _isRegister = false;
  bool _isLoadingAuth = false;

  final TextEditingController _serverUrlController = TextEditingController(
    text: pocketBaseService.serverUrl,
  );
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  Future<void> _submitOnboardingLogin() async {
    minimizeKeyboard(context);

    String serverUrl = _serverUrlController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    final String passwordConfirm = _passwordConfirmController.text;

    if (serverUrl.isEmpty) {
      openSnackbar(SnackbarMessage(
        title: "Server URL Required",
        description: "Please enter your PocketBase server URL.",
        icon: Icons.link_off_rounded,
      ));
      return;
    }

    if (!serverUrl.startsWith("http://") && !serverUrl.startsWith("https://")) {
      serverUrl = "https://$serverUrl";
      _serverUrlController.text = serverUrl;
    }

    if (email.isEmpty || !email.contains('@')) {
      openSnackbar(SnackbarMessage(
        title: "Invalid Email",
        description: "Please enter a valid email address.",
        icon: Icons.alternate_email_rounded,
      ));
      return;
    }

    if (password.isEmpty) {
      openSnackbar(SnackbarMessage(
        title: "Password Required",
        description: "Please enter your password.",
        icon: Icons.lock_outline,
      ));
      return;
    }

    if (_isRegister) {
      if (password.length < 8) {
        openSnackbar(SnackbarMessage(
          title: "Password Too Short",
          description: "Password must be at least 8 characters.",
          icon: Icons.lock_clock_outlined,
        ));
        return;
      }
      if (password != passwordConfirm) {
        openSnackbar(SnackbarMessage(
          title: "Passwords Do Not Match",
          description: "Please ensure both password fields match.",
          icon: Icons.error_outline,
        ));
        return;
      }
    }

    setState(() {
      _isLoadingAuth = true;
    });

    openLoadingPopup(context);

    try {
      await pocketBaseService.setServerUrl(serverUrl);

      if (_isRegister) {
        await pocketBaseService.register(email, password, passwordConfirm);
      } else {
        await pocketBaseService.login(email, password);
      }

      try {
        await pocketBaseSyncEngine.syncAll(forceFullSync: true);
      } catch (syncErr) {
        debugPrint("Initial onboarding sync error: $syncErr");
      }

      popRoute(context); // close loading popup

      openSnackbar(SnackbarMessage(
        title: _isRegister ? "Account Created" : "Welcome Back",
        description: "Connected to PocketBase successfully.",
        icon: Icons.check_circle_outline,
      ));

      await nextNavigation();
    } catch (e) {
      popRoute(context); // close loading popup
      final errorMsg = getPocketBaseErrorMessage(e);
      openSnackbar(SnackbarMessage(
        title: _isRegister ? "Registration Failed" : "Sign In Failed",
        description: errorMsg,
        icon: Icons.error_outline,
      ));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAuth = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _focusAttachment = _focusNode.attach(context, onKeyEvent: (node, event) {
      if (event.logicalKey.keyLabel == "Go Back" ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (widget.popNavigationWhenDone) nextNavigation();
      } else if (event.runtimeType == KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        nextOnBoardPage();
      } else if (event.runtimeType == KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        previousOnBoardPage();
      }
      return KeyEventResult.handled;
    });
    _focusNode.requestFocus();

    Future.delayed(Duration.zero, () async {
      // Functions to run after entire UI loaded - landing page
      // Run here too, so user has a wallet when creating first budget
      // We need to run this after the UI is loaded - after translations are loaded
      await initializeDefaultDatabase();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _serverUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void nextOnBoardPage() {
    if ((controller.page?.round().toInt() ?? 0) + 1 == numPages) {
      nextNavigation();
    } else {
      controller.nextPage(
        duration: Duration(milliseconds: 1100),
        curve: ElasticOutCurve(1.3),
      );
    }
  }

  void previousOnBoardPage() {
    controller.previousPage(
      duration: Duration(milliseconds: 1100),
      curve: ElasticOutCurve(1.3),
    );
  }

  int numPages = 3;
  @override
  Widget build(BuildContext context) {
    _focusAttachment.reparent();
    final List<Widget> children = [
      // OnBoardPage(
      //   widgets: [
      //     Container(
      //       constraints: BoxConstraints(
      //           maxWidth: MediaQuery.sizeOf(context).height <=
      //                   MediaQuery.sizeOf(context).width
      //               ? MediaQuery.sizeOf(context).height * 0.5
      //               : 300),
      //       child: Image(
      //         image: AssetImage("assets/landing/DepressedMan.png"),
      //       ),
      //     ),
      //     SizedBox(height: 15),
      //     Padding(
      //       padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
      //       child: TextFont(
      //         text: "Losing track of your spending?",
      //         fontWeight: FontWeight.bold,
      //         textAlign: TextAlign.center,
      //         fontSize: 25,
      //         maxLines: 5,
      //       ),
      //     ),
      //     SizedBox(height: 15),
      //     Padding(
      //       padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
      //       child: TextFont(
      //         text: "It's important to be mindful of your purchases.",
      //         textAlign: TextAlign.center,
      //         fontSize: 16,
      //         maxLines: 5,
      //       ),
      //     ),
      //   ],
      // ),
      OnBoardPage(
        widgets: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).height <=
                        MediaQuery.sizeOf(context).width
                    ? MediaQuery.sizeOf(context).height * 0.5
                    : 300),
            child: imageLanding1,
          ),
          SizedBox(height: 15),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
            child: TextFont(
              text: "onboarding-title-1".tr(namedArgs: {"app": globalAppName}),
              fontWeight: FontWeight.bold,
              textAlign: TextAlign.center,
              fontSize: 25,
              maxLines: 5,
            ),
          ),
          SizedBox(height: 15),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
            child: TextFont(
              text: "onboarding-info-1".tr(),
              textAlign: TextAlign.center,
              fontSize: 16,
              maxLines: 5,
            ),
          ),
          SizedBox(height: 55),
        ],
        bottomWidget: widget.showPreviewDemoButton
            ? PreviewDemoButton(
                nextNavigation: nextNavigation,
              )
            : null,
      ),
      OnBoardPage(
        widgets: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).height <=
                        MediaQuery.sizeOf(context).width
                    ? MediaQuery.sizeOf(context).height * 0.5
                    : 300),
            child: imageLanding2,
          ),
          SizedBox(height: 15),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
            child: TextFont(
              text: "onboarding-title-2".tr(),
              fontWeight: FontWeight.bold,
              textAlign: TextAlign.center,
              fontSize: 25,
              maxLines: 5,
            ),
          ),
          SizedBox(height: 10),
          BudgetDetails(
            determineBottomButton: () {},
            setSelectedAmount: (amount, _) {
              setState(() {
                selectedAmount = amount;
              });
            },
            initialSelectedAmount: selectedAmount,
            setSelectedPeriodLength: (length) {
              setState(() {
                selectedPeriodLength = length;
              });
            },
            initialSelectedPeriodLength: selectedPeriodLength,
            setSelectedRecurrence: (recurrence) {
              setState(() {
                selectedRecurrence = recurrence;
              });
            },
            initialSelectedRecurrence: selectedRecurrence,
            setSelectedStartDate: (date) {
              setState(() {
                selectedStartDate = date;
              });
            },
            initialSelectedStartDate: selectedStartDate,
            setSelectedEndDate: (date) {
              setState(() {
                selectedEndDate = date;
              });
            },
            initialSelectedEndDate: selectedEndDate,
          ),
          // This is pretty confusing, users can enable this later by editing the budget
          // Opacity(
          //   opacity: 0.8,
          //   child: ChoiceChip(
          //     materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          //     selectedColor: appStateSettings["materialYou"]
          //         ? null
          //         : getColor(context, "lightDarkAccentHeavy"),
          //     label: TextFont(
          //       text: "include-income-onboarding-label".tr() +
          //           (selectedIncludeIncome == false ? "?" : ""),
          //       fontSize: 15,
          //     ),
          //     selected: selectedIncludeIncome,
          //     onSelected: (bool selected) {
          //       setState(() {
          //         selectedIncludeIncome = selected;
          //       });
          //     },
          //   ),
          // ),

          StreamBuilder<AllWallets>(
            stream: database.watchAllWalletsIndexed(),
            builder: (context, snapshot) {
              TransactionWallet? primaryWallet = snapshot
                  .data?.indexedByPk[appStateSettings["selectedWalletPk"]];
              if (primaryWallet != null) {
                return Padding(
                  padding: const EdgeInsetsDirectional.only(top: 15),
                  child: LowKeyButton(
                    onTap: () {
                      openBottomSheet(
                        context,
                        SizedBox.shrink(),
                        customBuilder:
                            (context2, scrollController, sheetState) {
                          return CustomScrollView(
                            controller: scrollController,
                            slivers: [
                              SliverToBoxAdapter(
                                child: PopupFramework(
                                  title: "select-primary-currency".tr(),
                                  subtitle:
                                      "select-primary-currency-description"
                                          .tr(),
                                  child: SizedBox.shrink(),
                                  bottomSafeAreaExtraPadding: false,
                                ),
                              ),
                              CurrencyPicker(
                                showExchangeRateInfoNotice: false,
                                onSelected: (selectedCurrency) {
                                  popRoute(context);
                                  database.createOrUpdateWallet(
                                      primaryWallet.copyWith(
                                          currency: Value(selectedCurrency)));
                                },
                                initialCurrency: primaryWallet.currency,
                                onHasFocus: () {
                                  // Disable scroll when focus - because iOS header height is different than that of Android.
                                  // Future.delayed(Duration(milliseconds: 500), () {
                                  //   addWalletPageKey.currentState?.scrollTo(250);
                                  // });
                                },
                                unSelectedColor: appStateSettings["materialYou"]
                                    ? null
                                    : getColor(context, "canvasContainer"),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    text: "change-currency".tr(),
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
          SizedBox(height: 15),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
            child: TextFont(
              text: "onboarding-info-2-1".tr(),
              textAlign: TextAlign.center,
              fontSize: 15,
              maxLines: 5,
              textColor: getColor(context, "black").withOpacity(0.35),
            ),
          ),
        ],
      ),
      OnBoardPage(
        widgets: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).height <=
                        MediaQuery.sizeOf(context).width
                    ? MediaQuery.sizeOf(context).height * 0.5
                    : 300),
            child: imageLanding3,
          ),
          SizedBox(height: 15),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
            child: TextFont(
              text: "onboarding-title-3".tr(namedArgs: {"app": globalAppName}),
              fontWeight: FontWeight.bold,
              textAlign: TextAlign.center,
              fontSize: 25,
              maxLines: 5,
            ),
          ),
          SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 25),
            child: TextFont(
              text: "onboarding-info-3".tr(),
              textAlign: TextAlign.center,
              fontSize: 15,
              maxLines: 5,
              textColor: getColor(context, "black").withOpacity(0.5),
            ),
          ),
          SizedBox(height: 25),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 350),
            firstCurve: Curves.easeInOutCubic,
            secondCurve: Curves.easeInOutCubic,
            sizeCurve: Curves.easeInOutCubic,
            crossFadeState: _showLoginForm
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Column(
              children: [
                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Button(
                      label: "Sign In",
                      icon: Icons.login_rounded,
                      expandedLayout: true,
                      onTap: () {
                        setState(() {
                          _showLoginForm = true;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LowKeyButton(
                  onTap: () {
                    nextNavigation();
                  },
                  text: "continue-without-sign-in".tr(),
                ),
              ],
            ),
            secondChild: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: getColor(context, "canvasContainer"),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        TextInput(
                          labelText: "Server URL",
                          icon: Icons.dns_outlined,
                          controller: _serverUrlController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 16, vertical: 8),
                          onSubmitted: (_) => _emailFocus.requestFocus(),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: HorizontalBreak(),
                        ),
                        TextInput(
                          labelText: "Email",
                          icon: Icons.email_outlined,
                          controller: _emailController,
                          focusNode: _emailFocus,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 16, vertical: 8),
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: HorizontalBreak(),
                        ),
                        TextInput(
                          labelText: "Password",
                          icon: Icons.lock_outline,
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          textInputAction: _isRegister
                              ? TextInputAction.next
                              : TextInputAction.done,
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 16, vertical: 8),
                          onSubmitted: (_) {
                            if (_isRegister) {
                              _confirmFocus.requestFocus();
                            } else {
                              _submitOnboardingLogin();
                            }
                          },
                        ),
                        if (_isRegister) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: HorizontalBreak(),
                          ),
                          TextInput(
                            labelText: "Confirm Password",
                            icon: Icons.lock_reset_outlined,
                            controller: _passwordConfirmController,
                            focusNode: _confirmFocus,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 16, vertical: 8),
                            onSubmitted: (_) => _submitOnboardingLogin(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Button(
                        label: _isLoadingAuth
                            ? "Please wait..."
                            : (_isRegister ? "Sign Up" : "Sign In"),
                        icon: _isRegister
                            ? Icons.person_add_rounded
                            : Icons.login_rounded,
                        disabled: _isLoadingAuth,
                        expandedLayout: true,
                        onTap: _submitOnboardingLogin,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LowKeyButton(
                    text: _isRegister
                        ? "Already have an account? Sign In"
                        : "Don't have an account? Sign Up",
                    onTap: () {
                      setState(() {
                        _isRegister = !_isRegister;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  LowKeyButton(
                    text: "continue-without-sign-in".tr(),
                    onTap: () {
                      nextNavigation();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];

    if (numPages != children.length)
      print("Error: onboarding pages mismatch in length!");

    return Stack(
      children: [
        PageView(
          controller: controller,
          children: children,
        ),
        PositionedDirectional(
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 100,
              width: 1000,
              foregroundDecoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.background.withOpacity(0.0),
                    Theme.of(context).colorScheme.background,
                  ],
                  begin: AlignmentDirectional.topCenter,
                  end: AlignmentDirectional.bottomCenter,
                  stops: [0.1, 1],
                ),
              ),
            ),
          ),
        ),
        if (MediaQuery.viewInsetsOf(context).bottom == 0)
          Align(
            alignment: AlignmentDirectional.bottomCenter,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 18,
                vertical: 15,
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedBuilder(
                      animation: controller,
                      builder: (BuildContext context, Widget? child) {
                        int currentIndex =
                            controller.page?.round().toInt() ?? 0;
                        return AnimatedOpacity(
                          opacity: currentIndex <= 0 ? 0 : 1,
                          duration: Duration(milliseconds: 200),
                          child: ButtonIcon(
                            onTap: () {
                              previousOnBoardPage();
                            },
                            icon: getPlatform() == PlatformOS.isIOS
                                ? appStateSettings["outlinedIcons"]
                                    ? Icons.chevron_left_outlined
                                    : Icons.chevron_left_rounded
                                : appStateSettings["outlinedIcons"]
                                    ? Icons.arrow_back_outlined
                                    : Icons.arrow_back_rounded,
                            size: 50,
                            padding: getIsFullScreen(context) == false
                                ? EdgeInsetsDirectional.all(3)
                                : EdgeInsetsDirectional.all(6),
                          ),
                        );
                      },
                    ),
                    PageIndicator(
                        controller: controller, itemCount: children.length),
                    AnimatedBuilder(
                      animation: controller,
                      builder: (BuildContext context, Widget? child) {
                        int currentIndex =
                            controller.page?.round().toInt() ?? 0;
                        return AnimatedOpacity(
                          opacity: getPlatform() == PlatformOS.isIOS
                              ? 1
                              : currentIndex >= children.length - 1
                                  ? 0
                                  : 1,
                          duration: Duration(milliseconds: 200),
                          child: ButtonIcon(
                            onTap: () => nextOnBoardPage(),
                            icon: getPlatform() == PlatformOS.isIOS
                                ? appStateSettings["outlinedIcons"]
                                    ? Icons.chevron_right_outlined
                                    : Icons.chevron_right_rounded
                                : appStateSettings["outlinedIcons"]
                                    ? Icons.arrow_forward_outlined
                                    : Icons.arrow_forward_rounded,
                            size: 50,
                            padding: getIsFullScreen(context) == false
                                ? EdgeInsetsDirectional.all(3)
                                : EdgeInsetsDirectional.all(6),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class OnBoardPage extends StatelessWidget {
  const OnBoardPage({Key? key, required this.widgets, this.bottomWidget})
      : super(key: key);
  final List<Widget> widgets;
  final Widget? bottomWidget;
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: LinearGradientFadedEdges(
            gradientSize: 20,
            enableTop: getPlatform() == PlatformOS.isIOS,
            enableBottom: getPlatform() == PlatformOS.isIOS,
            enableStart: false,
            enableEnd: false,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                Column(
                  children: [
                    SizedBox(height: 20),
                    ...widgets,
                    SizedBox(height: 80),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
              bottom: 60 + MediaQuery.paddingOf(context).bottom),
          child: Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: bottomWidget ?? SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
