
import 'dart:core';

import 'package:solana_web3/buffer.dart';
import 'package:solana_web3/solana_web3.dart';
import 'pyth.dart';


// An update to the content of the solana account at `key` that occurred at `slot`. */
class AccountUpdate<T extends Object> {
  Pubkey key;
  AccountInfo<T> accountInfo;
  num slot;
  AccountUpdate(this.key, this.accountInfo, this.slot);
}

//
//  * Type of callback invoked whenever a pyth price account changes. The callback additionally
//  * gets `product`, which contains the metadata for this price account (e.g., that the symbol is "BTC/USD")
//  */
typedef PythPriceCallback =void Function(Product product, PriceData price);

//
//  * A price callback that additionally includes the raw solana account information. Use this if you need
//  * access to account keys and such.
//  */
typedef PythVerbosePriceCallback = void Function(
    AccountUpdate<ProductData> product, AccountUpdate<PriceData> price);

/// Mapping from solana clusters to the public key of the pyth program. */
final Map<String,String> clusterToPythProgramKey = {
  'mainnet-beta': 'FsJ3A3u2vn5cTVofAjvy6y5kwABJAqYWpe4975bi2epH',
  'devnet': 'gSbePebfvPy7tRqimPoVecS2UsBvYv46ynrzWocc92s',
  'pythtest-crosschain': 'gSbePebfvPy7tRqimPoVecS2UsBvYv46ynrzWocc92s',
  'testnet': '8tfDNiaEyrV6Q1U4DEXrEigs9DoDtkugzFbybENEbCDz',
  'pythtest-conformance': '8tfDNiaEyrV6Q1U4DEXrEigs9DoDtkugzFbybENEbCDz',
  'pythnet': 'FsJ3A3u2vn5cTVofAjvy6y5kwABJAqYWpe4975bi2epH',
  'localnet': 'gMYYig2utAxVoXnM9UhtTWrt8e7x2SVBZqsWZJeT5Gw',
};

/// Gets the public key of the Pyth program running on the given cluster. */
Pubkey getPythProgramKeyForCluster(String? cluster){
  if (clusterToPythProgramKey.containsKey(cluster)) {
    return Pubkey.fromString(clusterToPythProgramKey[cluster]!);
  } else {
    throw ArgumentError(
      'Invalid Solana cluster name: $cluster. Valid options'
    );
  }
}

/// Retrieves the RPC API URL for the specified Pyth cluster  */
String getPythClusterApiUrl(String cluster) {
  // TODO: Add pythnet when it's ready
  if (cluster == 'pythtest-conformance' || cluster == 'pythtest-crosschain') {
    return 'https://api.pythtest.pyth.network';
  } else if (cluster == 'pythnet') {
    return 'https://pythnet.rpcpool.com';
  } else if (cluster == 'localnet') {
    return 'http://localhost:8899';
  } else if (cluster == 'devnet'){
    return Cluster.devnet.uri.host;
  } else if (cluster == 'testnet'){
    return Cluster.testnet.uri.host;
  } else if (cluster == 'mainnet-beta'){
    return Cluster.mainnet.uri.host;
  }else{
    throw ArgumentError(
      'Invalid Solana cluster name: $cluster.'
    );
  }
}

//
//  * Reads Pyth price data from a solana web3 connection. This class uses a callback-driven model,
//  * similar to the solana web3 methods for tracking updates to accounts.
//  */
class PythConnection {
  Connection connection;
  Pubkey pythProgramKey;
  Commitment commitment;
  List<Pubkey>? feedIds;

  Map<String, AccountUpdate<ProductData>> productAccountKeyToProduct = {};
  Map<String, String> priceAccountKeyToProductAccountKey = {};

  List<PythVerbosePriceCallback> callbacks = [];

  handleProductAccount(Pubkey key, AccountInfo account) {
    if (account.data == null) {
      throw ArgumentError('account.data is null');
    }
    final accountList = account.data as List<dynamic>;
    final buffer = Buffer.fromString(accountList[0], BufferEncoding.base64);
    final productData = parseProductData(buffer);

    productAccountKeyToProduct[key.toString()] =
        AccountUpdate(key, recreateAccountInfo(account, productData), productData.version);

    if (productData.priceAccountKey != null) {
      priceAccountKeyToProductAccountKey[
          productData.priceAccountKey!.toString()] = key.toString();
    }
  }

  handlePriceAccount(Pubkey key, AccountInfo account, int slot) {
    final productUpdate = productAccountKeyToProduct[
        priceAccountKeyToProductAccountKey[key.toString()]];
    if (productUpdate == null) {
      // This shouldn't happen since we're subscribed to all of the program's accounts,
      // but let's be good defensive programmers.
      throw ArgumentError(
        'Got a price update for an unknown product. This is a bug in the library, please report it to the developers.',
      );
    }
    if (account.data == null) {
      throw ArgumentError('account.data is null');
    }
    final lst = account.data as List<dynamic>;
    const BufferEncoding encoding = BufferEncoding.base64;
    final Buffer buffer = Buffer.fromString(lst[0] as String, encoding);

    final priceData = parsePriceData(buffer, slot);
    final priceUpdate =
        AccountUpdate(key, recreateAccountInfo(account, priceData), slot);

    for (final callback in callbacks) {
      callback(productUpdate, priceUpdate);
    }
  }

  handleAccount(
      Pubkey key, AccountInfo account, bool productOnly, int slot) {
    if (account.data == null) {
      throw ArgumentError('account.data is null');
    }

    final lst = account.data as List<dynamic>;
    const BufferEncoding encoding = BufferEncoding.base64;
    final Buffer buffer = Buffer.fromString(lst[0] as String, encoding);

    final base = parseBaseData(buffer);

    // The pyth program owns accounts that don't contain pyth data, which we can safely ignore.
    if (base != null) {
      switch (base.type) {
        case AccountType.Mapping:
          // We can skip these because we're going to get every account owned by this program anyway.
          break;
        case AccountType.Product:
          // this.handleProductAccount(key, account, slot);
          handleProductAccount(key, account);
          break;
        case AccountType.Price:
          if (!productOnly) {
            handlePriceAccount(key, account, slot);
          }
          break;
        case AccountType.Test:
        case AccountType.Permission:
          break;
        default:
          throw ArgumentError(
              "Unknown account type: ${base.type}. Try upgrading pyth-client.");
      }
    }
  }

  // /** Create a PythConnection that reads its data from an underlying solana web3 connection.
  //  *  pythProgramKey is the public key of the Pyth program running on the chosen solana cluster.
  //  */
  PythConnection(
      this.connection, this.pythProgramKey, this.feedIds,
      [this.commitment = Commitment.finalized]);

  // /** Start receiving price updates. Once this method is called, any registered callbacks will be invoked
  //  *  each time a Pyth price account is updated.
  //  */
  start() async {
    var accounts =
        await connection.getProgramAccounts(pythProgramKey); //,
    // config: GetProgramAccountsConfig(commitment: this.commitment));
    // final currentSlot = await this.connection.getSlot(this.commitment)
    final currentSlot = await connection.getSlot(
        config: CommitmentAndMinContextSlotConfig(commitment: commitment));
    // Handle all accounts once since we need to handle product accounts
    // at least once
    for (final ProgramAccount account in accounts) {
      handleAccount(Pubkey.fromString(account.pubkey), account.account,
          true, currentSlot);
    }

    if (feedIds != null && feedIds!.isNotEmpty) {
      // Filter down to only the feeds we want
      final rawIDs = feedIds?.map((feed) => feed.toString());
      accounts = accounts
          .where((feed) => rawIDs!.contains(feed.pubkey.toString()))
          .toList();
      for (final account in accounts) {
        connection
          .accountSubscribe(
            Pubkey.fromString(account.pubkey),
            onData: (keyedAccountInfo) {
              handleAccount(
               Pubkey.fromString(account.pubkey),
               keyedAccountInfo, false, currentSlot);
            },
            onError: (err, [stack]){
              throw Exception("Account Subcscribe Error");
            },
            // onDone: () {
              // print("Done");
            // }, 
          );
      }
    } else {
        await connection
          .programSubscribe(
            pythProgramKey,
            onData: (keyedAccountInfo) {
              handleAccount(
               Pubkey.fromString(keyedAccountInfo.pubkey),
               keyedAccountInfo.account, false, currentSlot);
            },
            onError: (err, [stack]){
              throw Exception("Program Account Subcscribe Error");
            },
            // onDone: () {
              // print("Done");
            // },
          );
    }
  }

  // /** Register callback to receive price updates. */
  onPriceChange(PythPriceCallback callback) {
    callbacks.add((product, price) =>
        callback(product.accountInfo.data!.product, price.accountInfo.data!));
  }

  // /** Register a verbose callback to receive price updates. */
  onPriceChangeVerbose(PythVerbosePriceCallback callback) {
    callbacks.add(callback);
  }

  // /** Stop receiving price updates. Note that this also currently deletes all registered callbacks. */
  stop() async {
    // There's no way to actually turn off the solana web3 subscription x_x, but there should be.
    // Leave this method in so we don't have to update our API when solana fixes theirs.
    // In the interim, delete callbacks.
    callbacks = [];
  }
}
