import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:pos_desktop_clean/features/data/datasources/customers_remote_datasource.dart';
import 'package:pos_desktop_clean/features/data/datasources/payment_remote_datasource.dart';
import 'package:pos_desktop_clean/features/data/datasources/refunds_remote_datasource.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'package:pos_desktop_clean/core/di/api/app_config.dart';
import 'package:pos_desktop_clean/core/di/api/device_id_interceptor.dart';
import 'package:pos_desktop_clean/core/di/api/device_id_store.dart';

import 'package:pos_desktop_clean/features/data/datasources/local_pos_datasource.dart';
import 'package:pos_desktop_clean/features/data/repositories/pos_repository_impl.dart';
import 'package:pos_desktop_clean/features/domain/repositories/pos_repository.dart';

import 'package:pos_desktop_clean/features/data/datasources/auth_remote_datasource.dart';
import 'package:pos_desktop_clean/features/data/repositories/auth_repository_impl.dart';
import 'package:pos_desktop_clean/features/domain/repositories/auth_repository.dart';

import 'package:pos_desktop_clean/features/data/datasources/session_remote_datasource.dart';
import 'package:pos_desktop_clean/features/data/repositories/session_repository_impl.dart';
import 'package:pos_desktop_clean/features/domain/repositories/session_repository.dart';

import 'package:pos_desktop_clean/features/data/datasources/product_remote_datasource.dart';
import 'package:pos_desktop_clean/features/data/datasources/product_local_datasource.dart';
import 'package:pos_desktop_clean/features/data/repositories/product_repository_impl.dart';
import 'package:pos_desktop_clean/features/domain/repositories/product_repository.dart';

import 'package:pos_desktop_clean/features/data/datasources/sale_remote_datesource.dart';
import 'package:pos_desktop_clean/features/data/datasources/sale_local_datasource.dart';
import 'package:pos_desktop_clean/features/data/repositories/sale_repository_impl.dart';
import 'package:pos_desktop_clean/features/domain/repositories/sale_repository.dart';

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
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
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

  if (!sl.isRegistered<RefundsRemoteDatasource>()) {
    sl.registerLazySingleton<RefundsRemoteDatasource>(
      () => RefundsRemoteDatasource(sl<Dio>()),
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

  if (!sl.isRegistered<CustomersRemoteDataSource>()) {
    sl.registerLazySingleton<CustomersRemoteDataSource>(
      () => CustomersRemoteDataSource(sl<Dio>()),
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
