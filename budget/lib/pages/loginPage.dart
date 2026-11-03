import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/colors.dart';
import 'package:budget/database/initializeDefaultDatabase.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart' show HorizontalBreak;
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/languageMap.dart';
import 'package:budget/struct/pocketbaseService.dart';
import 'package:budget/struct/pocketbaseSync.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isRegister = false;
  bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    minimizeKeyboard(context);

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    final String passwordConfirm = _passwordConfirmController.text;

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
          description: "Please ensure both password fields match exactly.",
          icon: Icons.error_outline,
        ));
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    openLoadingPopup(context);

    try {
      if (_isRegister) {
        await pocketBaseService.register(email, password, passwordConfirm);
      } else {
        await pocketBaseService.login(email, password);
      }

      // Initial sync down from server
      try {
        await pocketBaseSyncEngine.syncAll(forceFullSync: true);
      } catch (syncError) {
        debugPrint("Initial sync error: $syncError");
      }

      // Ensure local database has at least the default initial setup if brand new
      int walletsCount = await database.getAmountOfWallets();
      if (walletsCount == 0) {
        await initializeDefaultDatabase();
      }

      // Mark onboarding completed
      await updateSettings("hasOnboarded", true,
          pagesNeedingRefresh: [], updateGlobalState: true);

      // Close loading popup
      popRoute(context);

      openSnackbar(SnackbarMessage(
        title: _isRegister ? "Account Created" : "Welcome Back",
        description: "Successfully connected to Cashon Cloud.",
        icon: Icons.check_circle_outline,
      ));
    } catch (e) {
      popRoute(context);
      final errorMsg = getPocketBaseErrorMessage(e);
      openSnackbar(SnackbarMessage(
        title: _isRegister ? "Registration Failed" : "Sign In Failed",
        description: errorMsg,
        icon: Icons.error_outline,
      ));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openServerConfigBottomSheet() {
    final TextEditingController urlController =
        TextEditingController(text: pocketBaseService.serverUrl);

    openBottomSheet(
      context,
      PopupFramework(
        title: "Server Endpoint",
        subtitle: "PocketBase URL",
        child: Column(
          children: [
            TextInput(
              labelText: "Server URL",
              controller: urlController,
              icon: Icons.link_rounded,
              padding: EdgeInsetsDirectional.zero,
              autoFocus: true,
            ),
            const SizedBox(height: 18),
            Button(
              label: "Save",
              icon: Icons.check_rounded,
              expandedLayout: true,
              onTap: () async {
                final newUrl = urlController.text.trim();
                if (newUrl.isNotEmpty &&
                    (newUrl.startsWith("http://") ||
                        newUrl.startsWith("https://"))) {
                  await pocketBaseService.setServerUrl(newUrl);
                  popRoute(context);
                  setState(() {});
                  openSnackbar(SnackbarMessage(
                    title: "Server URL Updated",
                    description: newUrl,
                    icon: Icons.check_rounded,
                  ));
                } else {
                  openSnackbar(SnackbarMessage(
                    title: "Invalid URL",
                    description: "Must start with http:// or https://",
                    icon: Icons.warning_amber_rounded,
                  ));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Icon / Graphic
                  Container(
                    height: 110,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: const Image(
                      image: AssetImage("assets/landing/BankOrPig.png"),
                      fit: BoxFit.contain,
                    ),
                  ),

                  // Brand Title
                  TextFont(
                    text: globalAppName,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  TextFont(
                    text: _isRegister
                        ? "Create an account to synchronize your finances."
                        : "Sign in to synchronize your finances across devices.",
                    fontSize: 15,
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    textColor: getColor(context, "black").withOpacity(0.55),
                  ),
                  const SizedBox(height: 28),

                  // Inputs Card
                  Container(
                    decoration: BoxDecoration(
                      color: getColor(context, "canvasContainer"),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
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
                              _submit();
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
                            icon: Icons.lock_outline,
                            controller: _passwordConfirmController,
                            focusNode: _confirmFocus,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 16, vertical: 8),
                            onSubmitted: (_) => _submit(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Action Button
                  Button(
                    label: _isLoading
                        ? "Please wait..."
                        : (_isRegister ? "Create Account" : "Sign In"),
                    icon: _isRegister
                        ? Icons.person_add_rounded
                        : Icons.login_rounded,
                    disabled: _isLoading,
                    expandedLayout: true,
                    onTap: _submit,
                  ),
                  const SizedBox(height: 12),

                  // Toggle Login / Register
                  LowKeyButton(
                    text: _isRegister
                        ? "Already have an account? Sign In"
                        : "Don't have an account? Create one",
                    onTap: () {
                      setState(() {
                        _isRegister = !_isRegister;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Backend server info pill
                  Tappable(
                    color: Colors.transparent,
                    borderRadius: 14,
                    onTap: _openServerConfigBottomSheet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_outlined,
                            size: 15,
                            color: getColor(context, "black").withOpacity(0.4),
                          ),
                          const SizedBox(width: 6),
                          TextFont(
                            text: pocketBaseService.serverUrl
                                .replaceFirst("https://", "")
                                .replaceFirst("http://", ""),
                            fontSize: 12,
                            textColor:
                                getColor(context, "black").withOpacity(0.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
