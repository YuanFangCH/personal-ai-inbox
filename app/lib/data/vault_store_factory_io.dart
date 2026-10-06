import 'io_vault_store.dart';
import 'vault_store.dart';

Future<VaultStore> createVaultStore() => IoVaultStore.create();
