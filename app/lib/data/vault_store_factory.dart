import 'vault_store.dart';
import 'vault_store_factory_io.dart'
    if (dart.library.js_interop) 'vault_store_factory_web.dart'
    as platform;

Future<VaultStore> createPlatformVaultStore() => platform.createVaultStore();
