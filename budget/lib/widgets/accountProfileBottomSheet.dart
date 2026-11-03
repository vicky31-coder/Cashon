import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/pocketbaseService.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';

void openAccountProfileBottomSheet(BuildContext context) {
  openBottomSheet(
    context,
    PopupFramework(
      title: "Account",
      subtitle: "Profile Details",
      child: const AccountProfileView(),
    ),
  );
}

class AccountProfileView extends StatefulWidget {
  const AccountProfileView({super.key});

  @override
  State<AccountProfileView> createState() => _AccountProfileViewState();
}

class _AccountProfileViewState extends State<AccountProfileView> {
  late TextEditingController _nameController;
  String? _selectedImagePath;
  bool _removePhoto = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    String currentName =
        pocketBaseService.userName ?? appStateSettings["username"] ?? "";
    _nameController = TextEditingController(text: currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
          _removePhoto = false;
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      openSnackbar(SnackbarMessage(
        title: "Image Selection Failed",
        description: e.toString(),
        icon: Icons.error_outline,
      ));
    }
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim();
    setState(() {
      _isSaving = true;
    });

    try {
      if (_removePhoto) {
        await sharedPreferences.remove("user_avatar_path");
      }

      await pocketBaseService.updateProfile(
        name: newName,
        avatarFilePath: _removePhoto ? null : _selectedImagePath,
      );

      // Force UI updates
      appStateKey.currentState?.refreshAppState();
      popRoute(context);

      openSnackbar(SnackbarMessage(
        title: "Account Updated",
        description: "Profile information saved successfully.",
        icon: Icons.check_circle_outline,
      ));
    } catch (e) {
      openSnackbar(SnackbarMessage(
        title: "Update Failed",
        description: e.toString(),
        icon: Icons.error_outline,
      ));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildAvatar(BuildContext context) {
    String name = _nameController.text.trim();
    if (name.isEmpty) {
      name = pocketBaseService.userEmail?.split("@").first ?? "U";
    }
    String initial = name.isNotEmpty ? name[0].toUpperCase() : "U";

    String? currentLocalAvatar =
        sharedPreferences.getString("user_avatar_path");
    String? currentPbAvatar = pocketBaseService.userAvatarUrl;

    ImageProvider? imageProvider;
    if (!_removePhoto) {
      if (_selectedImagePath != null && File(_selectedImagePath!).existsSync()) {
        imageProvider = FileImage(File(_selectedImagePath!));
      } else if (currentLocalAvatar != null &&
          currentLocalAvatar.isNotEmpty &&
          File(currentLocalAvatar).existsSync()) {
        imageProvider = FileImage(File(currentLocalAvatar));
      } else if (currentPbAvatar != null &&
          currentPbAvatar.isNotEmpty &&
          currentPbAvatar.startsWith("http")) {
        imageProvider = NetworkImage(currentPbAvatar);
      }
    }

    return Center(
      child: Stack(
        children: [
          Tappable(
            color: Colors.transparent,
            borderRadius: 100,
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 46,
              backgroundColor: dynamicPastel(
                context,
                Theme.of(context).colorScheme.primary,
                amount: 0.2,
              ),
              backgroundImage: imageProvider,
              child: imageProvider == null
                  ? TextFont(
                      text: initial,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      textColor: dynamicPastel(
                        context,
                        Theme.of(context).colorScheme.primary,
                        amount: 0.85,
                        inverse: false,
                      ),
                    )
                  : null,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Tappable(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: 100,
              onTap: _pickImage,
              child: Padding(
                padding: const EdgeInsets.all(7.0),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = pocketBaseService.userEmail ?? "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _buildAvatar(context),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LowKeyButton(
              text: "Change Photo",
              onTap: _pickImage,
            ),
            if (_selectedImagePath != null ||
                sharedPreferences.getString("user_avatar_path") != null ||
                (pocketBaseService.userAvatarUrl != null &&
                    pocketBaseService.userAvatarUrl!.isNotEmpty)) ...[
              const SizedBox(width: 8),
              LowKeyButton(
                text: "Remove",
                onTap: () {
                  setState(() {
                    _selectedImagePath = null;
                    _removePhoto = true;
                  });
                },
              ),
            ],
          ],
        ),

        const SizedBox(height: 16),
        TextInput(
          labelText: "Name",
          controller: _nameController,
          icon: Icons.person_outline_rounded,
          padding: EdgeInsetsDirectional.zero,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextInput(
          labelText: "Email",
          initialValue: email,
          icon: Icons.email_outlined,
          readOnly: true,
          padding: EdgeInsetsDirectional.zero,
        ),
        const SizedBox(height: 22),
        Button(
          label: _isSaving ? "Saving..." : "Save Changes",
          icon: Icons.check_rounded,
          disabled: _isSaving,
          expandedLayout: true,
          onTap: _save,
        ),
      ],
    );
  }
}
