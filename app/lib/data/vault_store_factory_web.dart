import 'vault_store.dart';
import 'web_vault_store.dart';

Future<VaultStore> createVaultStore() => WebVaultStore.create();
