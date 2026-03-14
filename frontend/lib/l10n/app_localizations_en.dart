// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RE Follow-Up Bot';

  @override
  String get signIn => 'Sign In';

  @override
  String get register => 'Register';

  @override
  String get createAccount => 'Create Account';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get fullName => 'Full name';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get sendResetLink => 'Send Reset Link';

  @override
  String get clients => 'Clients';

  @override
  String get addClient => 'Add Client';

  @override
  String get sendNow => 'Send Now';

  @override
  String get refresh => 'Refresh';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get markAsReplied => 'Mark as replied';

  @override
  String get clientInformation => 'Client Information';

  @override
  String get followUpMessages => 'Follow-up Messages';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get notes => 'Notes';

  @override
  String get propertyLink => 'Property link';

  @override
  String get whatsAppPhone => 'WhatsApp phone';

  @override
  String get required => 'Required';

  @override
  String get passwordMinChars => 'Min 8 characters';

  @override
  String get invalidResetLink => 'Invalid reset link';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordUpdated => 'Password updated!';

  @override
  String get goToSignIn => 'Go to Sign In';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get signOut => 'Sign out';

  @override
  String get whatsappStatus => 'WhatsApp: ';

  @override
  String get schedulerRunning =>
      'Scheduler: running — fires automatically when messages are due.';

  @override
  String get totalClients => 'Total Clients';

  @override
  String get active => 'Active';

  @override
  String get replied => 'Replied';

  @override
  String get msgsSent => 'Msgs Sent';

  @override
  String get pending => 'Pending';

  @override
  String get failed => 'Failed';

  @override
  String sentMessages(Object count) {
    return 'Sent $count message(s)';
  }

  @override
  String error(Object error) {
    return 'Error: $error';
  }

  @override
  String markAsRepliedConfirm(Object name) {
    return 'Mark $name as replied?\nAll pending follow-ups will be cancelled.';
  }

  @override
  String get deleteClient => 'Delete client';

  @override
  String deleteClientConfirm(Object name) {
    return 'Permanently delete $name and all their messages?';
  }

  @override
  String get noClients => 'No clients yet. Click Add Client to get started.';

  @override
  String get statusActive => 'Active';

  @override
  String get statusReplied => 'Replied';

  @override
  String get yourEmail => 'Your email';

  @override
  String get resetLinkSent => 'If that email exists, a reset link was sent.';

  @override
  String get passwordMinHint => 'Password (min 8 chars)';

  @override
  String get editClient => 'Edit Client';

  @override
  String get fullNameRequired => 'Full name *';

  @override
  String get whatsappPhoneRequired => 'WhatsApp phone *';

  @override
  String messageNumber(Object number) {
    return 'Message $number';
  }

  @override
  String get messageBodyHint => 'Message body...';

  @override
  String get change => 'Change';

  @override
  String get placeholdersHelp =>
      'Placeholders: [name]  [property_link]  [email]';

  @override
  String get missingResetToken =>
      'This link is missing a reset token. Please request a new password reset.';

  @override
  String get setNewPassword => 'Set new password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get passwordChangedSuccess =>
      'Your password has been changed. You can now sign in.';
}
