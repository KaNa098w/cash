import 'package:get_it/get_it.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/auth_repository_impl.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/auth_repository.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/auth_repository.dart';
import 'package:pos_desktop_clean/features/pos/presentation/state/auth_cubit.dart';

// POS
import '../../features/pos/data/datasources/local_pos_datasource.dart';
import '../../features/pos/data/repositories/pos_repository_impl.dart';
import '../../features/pos/domain/repositories/pos_repository.dart';
import '../../features/pos/presentation/state/pos_cubit.dart';


final sl = ServiceLocator.instance.getIt;

class ServiceLocator {
  ServiceLocator._();
  static final instance = ServiceLocator._();
  final getIt = GetIt.instance;

  Future<void> init() async {
    // Data sources
    getIt.registerLazySingleton<LocalPosDataSource>(() => LocalPosDataSource());

    // Repositories
    getIt.registerLazySingleton<PosRepository>(() => PosRepositoryImpl(getIt()));

    // --- AUTH ---
    getIt.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl());

    // Cubits
    getIt.registerFactory(() => PosCubit(getIt()));
    getIt.registerLazySingleton<AuthCubit>(() => AuthCubit(getIt<AuthRepository>()));
  }
}
