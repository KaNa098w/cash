import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/payment_remote_datasource.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'package:pos_desktop_clean/core/di/api/app_config.dart';
import 'package:pos_desktop_clean/core/di/api/device_id_interceptor.dart';
import 'package:pos_desktop_clean/core/di/api/device_id_store.dart';

// POS
import 'package:pos_desktop_clean/features/pos/data/datasources/local_pos_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/pos_repository.dart';

// AUTH
import 'package:pos_desktop_clean/features/pos/data/datasources/auth_remote_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/auth_repository_impl.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/auth_repository.dart';

// SESSION
import 'package:pos_desktop_clean/features/pos/data/datasources/session_remote_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/session_repository_impl.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/session_repository.dart';

// PRODUCTS
import 'package:pos_desktop_clean/features/pos/data/datasources/product_remote_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/product_local_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/product_repository_impl.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/product_repository.dart';

// SALES
import 'package:pos_desktop_clean/features/pos/data/datasources/sale_remote_datesource.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/sale_local_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/sale_repository_impl.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/sale_repository.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // ✅ store для deviceId
  if (!sl.isRegistered<DeviceIdStore>()) {
    sl.registerLazySingleton<DeviceIdStore>(() => DeviceIdStore());
  }

  // ---------- Dio / HTTP ----------
  if (!sl.isRegistered<Dio>()) {
    sl.registerLazySingleton<Dio>(() {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.I.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          contentType: 'application/json',
          headers: const {
            'Accept': 'application/json',
          },
        ),
      );

      // ✅ авто-добавление device_id
      dio.interceptors.add(DeviceIdInterceptor(sl<DeviceIdStore>()));

      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
          compact: true,
          maxWidth: 120,
          logPrint: (obj) => debugPrint(obj.toString()),
        ),
      );

      return dio;
    });
  }

  // ---------- Data sources ----------
  if (!sl.isRegistered<LocalPosDataSource>()) {
    sl.registerLazySingleton<LocalPosDataSource>(() => LocalPosDataSource());
  }

  if (!sl.isRegistered<AuthRemoteDataSource>()) {
    sl.registerLazySingleton<AuthRemoteDataSource>(
      () => AuthRemoteDataSource(sl<Dio>()),
    );
  }

  if (!sl.isRegistered<SessionRemoteDataSource>()) {
    sl.registerLazySingleton<SessionRemoteDataSource>(
      () => SessionRemoteDataSource(sl<Dio>()),
    );
  }

  if (!sl.isRegistered<ProductRemoteDataSource>()) {
    sl.registerLazySingleton<ProductRemoteDataSource>(
      () => ProductRemoteDataSource(sl<Dio>()),
    );
  }

  if (!sl.isRegistered<ProductLocalDataSource>()) {
    sl.registerLazySingleton<ProductLocalDataSource>(
      () => ProductLocalDataSource(),
    );
  }

  if (!sl.isRegistered<SaleRemoteDataSource>()) {
    sl.registerLazySingleton<SaleRemoteDataSource>(
      () => SaleRemoteDataSource(sl<Dio>()),
    );
  }

  if (!sl.isRegistered<SaleLocalDataSource>()) {
    sl.registerLazySingleton<SaleLocalDataSource>(
      () => SaleLocalDataSource(),
    );
  }

  // ---------- Repositories ----------
  if (!sl.isRegistered<PosRepository>()) {
    sl.registerLazySingleton<PosRepository>(
      () => PosRepositoryImpl(sl<LocalPosDataSource>()),
    );
  }

  if (!sl.isRegistered<AuthRepository>()) {
    sl.registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(sl<AuthRemoteDataSource>()),
    );
  }

  // ✅ SESSION repository
  if (!sl.isRegistered<SessionRepository>()) {
    sl.registerLazySingleton<SessionRepository>(
      () => SessionRepositoryImpl(sl<SessionRemoteDataSource>()),
    );
  }

  if (!sl.isRegistered<ProductRepository>()) {
    sl.registerLazySingleton<ProductRepository>(
      () => ProductRepositoryImpl(
        sl<ProductRemoteDataSource>(),
        sl<ProductLocalDataSource>(),
      ),
    );
  }

  sl.registerLazySingleton<PaymentsRemoteDataSource>(
    () => PaymentsRemoteDataSource(sl<Dio>()),
  );

  if (!sl.isRegistered<SaleRepository>()) {
    sl.registerLazySingleton<SaleRepository>(
      () => SaleRepositoryImpl(
        sl<SaleRemoteDataSource>(),
        sl<SaleLocalDataSource>(),
      ),
    );
  }
}
