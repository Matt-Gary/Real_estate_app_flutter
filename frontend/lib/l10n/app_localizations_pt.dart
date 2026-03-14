// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'RE Follow-Up Bot';

  @override
  String get signIn => 'Entrar';

  @override
  String get register => 'Registrar';

  @override
  String get createAccount => 'Criar Conta';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Senha';

  @override
  String get fullName => 'Nome completo';

  @override
  String get forgotPassword => 'Esqueceu a senha?';

  @override
  String get resetPassword => 'Redefinir Senha';

  @override
  String get sendResetLink => 'Enviar Link de Redefinição';

  @override
  String get clients => 'Clientes';

  @override
  String get addClient => 'Adicionar Cliente';

  @override
  String get sendNow => 'Enviar Agora';

  @override
  String get refresh => 'Atualizar';

  @override
  String get edit => 'Editar';

  @override
  String get delete => 'Excluir';

  @override
  String get markAsReplied => 'Marcar como respondido';

  @override
  String get clientInformation => 'Informações do Cliente';

  @override
  String get followUpMessages => 'Mensagens de Acompanhamento';

  @override
  String get save => 'Salvar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get notes => 'Notas';

  @override
  String get propertyLink => 'Link do imóvel';

  @override
  String get whatsAppPhone => 'WhatsApp';

  @override
  String get required => 'Obrigatório';

  @override
  String get passwordMinChars => 'Mínimo de 8 caracteres';

  @override
  String get invalidResetLink => 'Link de redefinição inválido';

  @override
  String get passwordsDoNotMatch => 'As senhas não coincidem';

  @override
  String get passwordUpdated => 'Senha atualizada!';

  @override
  String get goToSignIn => 'Ir para o login';

  @override
  String get dashboard => 'Painel';

  @override
  String get signOut => 'Sair';

  @override
  String get whatsappStatus => 'WhatsApp: ';

  @override
  String get schedulerRunning =>
      'Agendador: rodando — dispara automaticamente quando as mensagens vencem.';

  @override
  String get totalClients => 'Total de Clientes';

  @override
  String get active => 'Ativo';

  @override
  String get replied => 'Respondido';

  @override
  String get msgsSent => 'Msgs Enviadas';

  @override
  String get pending => 'Pendente';

  @override
  String get failed => 'Falhou';

  @override
  String sentMessages(Object count) {
    return '$count mensagem(ns) enviada(s)';
  }

  @override
  String error(Object error) {
    return 'Erro: $error';
  }

  @override
  String markAsRepliedConfirm(Object name) {
    return 'Marcar $name como respondido?\nTodos os acompanhamentos pendentes serão cancelados.';
  }

  @override
  String get deleteClient => 'Excluir cliente';

  @override
  String deleteClientConfirm(Object name) {
    return 'Excluir permanentemente $name e todas as suas mensagens?';
  }

  @override
  String get noClients =>
      'Nenhum cliente ainda. Clique em Adicionar Cliente para começar.';

  @override
  String get statusActive => 'Ativo';

  @override
  String get statusReplied => 'Respondido';

  @override
  String get yourEmail => 'Seu e-mail';

  @override
  String get resetLinkSent =>
      'Se esse e-mail existir, um link de redefinição foi enviado.';

  @override
  String get passwordMinHint => 'Senha (mínimo 8 caracteres)';

  @override
  String get editClient => 'Editar Cliente';

  @override
  String get fullNameRequired => 'Nome completo *';

  @override
  String get whatsappPhoneRequired => 'WhatsApp *';

  @override
  String messageNumber(Object number) {
    return 'Mensagem $number';
  }

  @override
  String get messageBodyHint => 'Corpo da mensagem...';

  @override
  String get change => 'Alterar';

  @override
  String get placeholdersHelp => 'Atalhos: [name]  [property_link]  [email]';

  @override
  String get missingResetToken =>
      'Este link não possui um token de redefinição. Solicite uma nova redefinição de senha.';

  @override
  String get setNewPassword => 'Definir nova senha';

  @override
  String get newPassword => 'Nova senha';

  @override
  String get confirmNewPassword => 'Confirmar nova senha';

  @override
  String get passwordChangedSuccess =>
      'Sua senha foi alterada. Agora você pode entrar.';
}
