import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';

class PenjualanState {
  final String number;
  final int storeID;
  final String storeName;
  final int organisasiID;
  final int salesTipeID;
  final int? memberID;
  final String memberNama;
  final List<CartItem> items;
  final double gross;
  final double diskon;
  final double total;
  final double dpp;
  final double pajak;
  final int caraBayarID;
  final double nominalBayar;
  final String returSource;

  PenjualanState({
    this.number = '',
    this.storeID = 0,
    this.storeName = '',
    this.organisasiID = 0,
    this.salesTipeID = 1,
    this.memberID,
    this.memberNama = '',
    this.items = const [],
    this.gross = 0,
    this.diskon = 0,
    this.total = 0,
    this.dpp = 0,
    this.pajak = 0,
    this.caraBayarID = 0,
    this.nominalBayar = 0,
    this.returSource = '',
  });

  PenjualanState copyWith({
    String? number,
    int? storeID,
    String? storeName,
    int? organisasiID,
    int? salesTipeID,
    int? memberID,
    String? memberNama,
    List<CartItem>? items,
    double? gross,
    double? diskon,
    double? total,
    double? dpp,
    double? pajak,
    int? caraBayarID,
    double? nominalBayar,
    String? returSource,
  }) {
    return PenjualanState(
      number: number ?? this.number,
      storeID: storeID ?? this.storeID,
      storeName: storeName ?? this.storeName,
      organisasiID: organisasiID ?? this.organisasiID,
      salesTipeID: salesTipeID ?? this.salesTipeID,
      memberID: memberID ?? this.memberID,
      memberNama: memberNama ?? this.memberNama,
      items: items ?? this.items,
      gross: gross ?? this.gross,
      diskon: diskon ?? this.diskon,
      total: total ?? this.total,
      dpp: dpp ?? this.dpp,
      pajak: pajak ?? this.pajak,
      caraBayarID: caraBayarID ?? this.caraBayarID,
      nominalBayar: nominalBayar ?? this.nominalBayar,
      returSource: returSource ?? this.returSource,
    );
  }
}

class PenjualanNotifier extends StateNotifier<PenjualanState> {
  PenjualanNotifier() : super(PenjualanState());

  void setInitialData({
    required String number,
    required int storeID,
    required String storeName,
    required int organisasiID,
    required int salesTipeID,
  }) {
    state = state.copyWith(
      number: number,
      storeID: storeID,
      storeName: storeName,
      organisasiID: organisasiID,
      salesTipeID: salesTipeID,
    );
  }

  void setMember(int? memberID, String memberNama) {
    state = state.copyWith(
      memberID: memberID,
      memberNama: memberNama,
    );
  }

  void setSalesTipe(int salesTipeID) {
    state = state.copyWith(salesTipeID: salesTipeID);
  }

  void setCaraBayar(int caraBayarID) {
    state = state.copyWith(caraBayarID: caraBayarID);
  }

  void setNominalBayar(double nominal) {
    state = state.copyWith(nominalBayar: nominal);
  }

  void updateItems(List<CartItem> items) {
    double gross = 0;
    double diskon = 0;
    double total = 0;

    for (var item in items) {
      gross += item.gross;
      diskon += item.gross - item.subtotal;
      total += item.subtotal;
    }

    state = state.copyWith(
      items: items,
      gross: gross,
      diskon: diskon,
      total: total,
    );
  }

  void updateSummary({
    required double gross,
    required double diskon,
    required double total,
    required double dpp,
    required double pajak,
  }) {
    state = state.copyWith(
      gross: gross,
      diskon: diskon,
      total: total,
      dpp: dpp,
      pajak: pajak,
    );
  }

  void reset() {
    state = PenjualanState();
  }

  void setReturSource(String source) {
    state = state.copyWith(returSource: source);
  }
}

final penjualanProvider =
    StateNotifierProvider<PenjualanNotifier, PenjualanState>(
  (ref) => PenjualanNotifier(),
);
