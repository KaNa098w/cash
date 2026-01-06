// // lib/features/pos/presentation/pages/preloader/preloader_page.dart

// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:go_router/go_router.dart';
// import 'package:provider/provider.dart';

// import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
// import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_cubit.dart';
// import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_state.dart';

// class PreloaderPage extends StatelessWidget {
//   const PreloaderPage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final auth = context.watch<AuthTokenProvider>();
//     final posKey = auth.posKey?.trim() ?? '';

//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: BlocListener<ProductsCubit, ProductsState>(
//         listenWhen: (prev, curr) => curr is ProductsLoaded,
//         listener: (context, state) {
//           if (state is ProductsLoaded) {
//             context.go('/pos');
//           }
//         },
//         child: Center(
//           child: BlocBuilder<ProductsCubit, ProductsState>(
//             builder: (context, state) {
//               // если ключа нет — возвращаем на экран ввода ключа
//               if (posKey.isEmpty) {
//                 WidgetsBinding.instance.addPostFrameCallback((_) {
//                   context.go('/login'); // поправь на свой маршрут
//                 });
//                 return const CircularProgressIndicator();
//               }

//               if (state is ProductsInitial) {
//                 // стартуем загрузку один раз
//                 WidgetsBinding.instance.addPostFrameCallback((_) {
//                   context.read<ProductsCubit>().loadFirstPage(
//                         forceRefresh: false,
//                         key: posKey,
//                       );
//                 });
//                 return const CircularProgressIndicator();
//               }

//               if (state is ProductsLoading) {
//                 return const CircularProgressIndicator();
//               }

//               if (state is ProductsError) {
//                 return Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Text('Ошибка: ${state.message}'),
//                     const SizedBox(height: 16),
//                     ElevatedButton(
//                       onPressed: () {
//                         context.read<ProductsCubit>().loadFirstPage(
//                               forceRefresh: true,
//                               key: posKey,
//                             );
//                       },
//                       child: const Text('Повторить'),
//                     ),
//                   ],
//                 );
//               }

//               // ProductsLoaded / другие – навигацией занимается BlocListener
//               return const SizedBox.shrink();
//             },
//           ),
//         ),
//       ),
//     );
//   }
// }
