import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'RE Follow-Up Bot'**
  String get appTitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLink;

  /// No description provided for @clients.
  ///
  /// In en, this message translates to:
  /// **'Clients'**
  String get clients;

  /// No description provided for @addClient.
  ///
  /// In en, this message translates to:
  /// **'Add Client'**
  String get addClient;

  /// No description provided for @sendNow.
  ///
  /// In en, this message translates to:
  /// **'Send Now'**
  String get sendNow;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @markAsReplied.
  ///
  /// In en, this message translates to:
  /// **'Mark as replied'**
  String get markAsReplied;

  /// No description provided for @clientInformation.
  ///
  /// In en, this message translates to:
  /// **'Client Information'**
  String get clientInformation;

  /// No description provided for @followUpMessages.
  ///
  /// In en, this message translates to:
  /// **'Follow-up Messages'**
  String get followUpMessages;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @propertyLink.
  ///
  /// In en, this message translates to:
  /// **'Property link'**
  String get propertyLink;

  /// No description provided for @whatsAppPhone.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp phone'**
  String get whatsAppPhone;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @passwordMinChars.
  ///
  /// In en, this message translates to:
  /// **'Min 8 characters'**
  String get passwordMinChars;

  /// No description provided for @invalidResetLink.
  ///
  /// In en, this message translates to:
  /// **'Invalid reset link'**
  String get invalidResetLink;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated!'**
  String get passwordUpdated;

  /// No description provided for @goToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Go to Sign In'**
  String get goToSignIn;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @whatsappStatus.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp: '**
  String get whatsappStatus;

  /// No description provided for @schedulerRunning.
  ///
  /// In en, this message translates to:
  /// **'Scheduler: running — fires automatically when messages are due.'**
  String get schedulerRunning;

  /// No description provided for @totalClients.
  ///
  /// In en, this message translates to:
  /// **'Total Clients'**
  String get totalClients;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @replied.
  ///
  /// In en, this message translates to:
  /// **'Replied'**
  String get replied;

  /// No description provided for @msgsSent.
  ///
  /// In en, this message translates to:
  /// **'Msgs Sent'**
  String get msgsSent;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @sentMessages.
  ///
  /// In en, this message translates to:
  /// **'Sent {count} message(s)'**
  String sentMessages(Object count);

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error(Object error);

  /// No description provided for @markAsRepliedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Mark {name} as replied?\nAll pending follow-ups will be cancelled.'**
  String markAsRepliedConfirm(Object name);

  /// No description provided for @deleteClient.
  ///
  /// In en, this message translates to:
  /// **'Delete client'**
  String get deleteClient;

  /// No description provided for @deleteClientConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {name} and all their messages?'**
  String deleteClientConfirm(Object name);

  /// No description provided for @noClients.
  ///
  /// In en, this message translates to:
  /// **'No clients yet. Click Add Client to get started.'**
  String get noClients;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusReplied.
  ///
  /// In en, this message translates to:
  /// **'Replied'**
  String get statusReplied;

  /// No description provided for @yourEmail.
  ///
  /// In en, this message translates to:
  /// **'Your email'**
  String get yourEmail;

  /// No description provided for @resetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'If that email exists, a reset link was sent.'**
  String get resetLinkSent;

  /// No description provided for @passwordMinHint.
  ///
  /// In en, this message translates to:
  /// **'Password (min 8 chars)'**
  String get passwordMinHint;

  /// No description provided for @editClient.
  ///
  /// In en, this message translates to:
  /// **'Edit Client'**
  String get editClient;

  /// No description provided for @fullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name *'**
  String get fullNameRequired;

  /// No description provided for @whatsappPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp phone *'**
  String get whatsappPhoneRequired;

  /// No description provided for @messageNumber.
  ///
  /// In en, this message translates to:
  /// **'Message {number}'**
  String messageNumber(Object number);

  /// No description provided for @messageBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Message body...'**
  String get messageBodyHint;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @placeholdersHelp.
  ///
  /// In en, this message translates to:
  /// **'Placeholders: [name]  [property_link]  [email]'**
  String get placeholdersHelp;

  /// No description provided for @missingResetToken.
  ///
  /// In en, this message translates to:
  /// **'This link is missing a reset token. Please request a new password reset.'**
  String get missingResetToken;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get setNewPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your password has been changed. You can now sign in.'**
  String get passwordChangedSuccess;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
