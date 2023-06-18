import 'package:solana_web3/buffer.dart';
import 'package:solana_web3/solana_web3.dart';
import 'pyth.dart';

class PythHttpClientResult {
  List<String> assetTypes;
  // /** The name of each product, e.g., "Crypto.BTC/USD" */
  List<String> symbols;
  List<Product> products;
  // /** Metadata for each product. */
  Map<String,Product> productFromSymbol;
  // /** The current price of each product. */
  Map<String,PriceData> productPrice;
  List<PriceData> prices;
  PermissionData? permissionData;

  PythHttpClientResult(this.assetTypes, this.symbols,this.products,this.productFromSymbol,this.productPrice,this.prices,this.permissionData);
}

// /**
//  * Reads Pyth price data from a solana web3 connection. This class uses a single HTTP call.
//  * Use the method getData() to get updated prices values.
//  */
class PythHttpClient {
  Connection connection;
  Pubkey pythProgramKey;
  Commitment commitment;

  PythHttpClient(this.connection, this.pythProgramKey, [this.commitment = Commitment.finalized]) ;

  // /*
  //  * Get Pyth Network account information and return actual price state.
  //  * The result contains lists of asset types, product symbols and their prices.
  //  */
  Future<PythHttpClientResult> getData()async{
    Set<String> assetTypes = <String>{};
    Set<String> productSymbols = <String>{};
    Set<Product> products = <Product>{};
    Map<String,Product> productFromSymbol ={};
    Map<String, PriceData> productPrice = {};
    List<PriceData> prices = [];

    final config = GetProgramAccountsConfig(commitment: commitment);
    // Retrieve data from blockchain
    final accountList = await connection.getProgramAccounts(pythProgramKey, config: config);

    // Populate products and prices
    final List<PriceData> priceDataQueue = [];
    final Map<String,Product>productAccountKeyToProduct = {};
    final currentSlot = await connection.getSlot(config: CommitmentAndMinContextSlotConfig(commitment: commitment));

    // Initialize permission field as undefined
    PermissionData? permissionData ;
    for(final singleAccount in accountList){
      // final base = parseBaseData(singleAccount.account.data as Buffer);
      final accountData = singleAccount.account.data as List<dynamic>;
      final accountDataBuffer = Buffer.fromString(accountData[0], BufferEncoding.base64);
      final base = parseBaseData(accountDataBuffer);
      if (base != null) {
        switch (base.type) {
          case AccountType.Mapping:
            // We can skip these because we're going to get every account owned by this program anyway.
            break;
          case AccountType.Product:
            final productData = parseProductData(accountDataBuffer);

            // productAccountKeyToProduct[singleAccount.pubkey.toBase58()]= productData.product;
            if(productData.product.isNotEmpty
              && productData.product.containsKey("asset_type") 
              && productData.product.containsKey("symbol")){
                productAccountKeyToProduct[singleAccount.pubkey]= productData.product;
                assetTypes.add(productData.product["asset_type"]!);
                productSymbols.add(productData.product["symbol"]!);
                products.add(productData.product);
                productFromSymbol[productData.product["symbol"]!] = productData.product;
            }
            break;
          case AccountType.Price:
            final priceData = parsePriceData(accountDataBuffer, currentSlot);
            priceDataQueue.add(priceData);
            break;
          case AccountType.Test:
            break;
          case AccountType.Permission:
            permissionData = parsePermissionData(accountDataBuffer);
            break;

          default:
            throw Exception("Unknown account type: ${base.type}. Try upgrading pyth-client.");
        }
      }
    }

    for(final priceData in priceDataQueue){
      // final product = productAccountKeyToProduct[priceData.productAccountKey.toBase58()];
      final product = productAccountKeyToProduct[priceData.productAccountKey.toBase58()];

      if (product != null) {
        productPrice[product["symbol"]!] =  priceData;
        prices.add(priceData);
      }
    }

    final result =  PythHttpClientResult(
      assetTypes.toList(),
      productSymbols.toList(),
      products.toList(),
      productFromSymbol,
      productPrice,
      prices,
      permissionData,
    );

    return result;
  }

  // /**
  //  * Get the price state for an array of specified price accounts.
  //  * The result is the price state for the given assets if they exist, throws if at least one account does not exist.
  //  */
  Future<List<PriceData>> getAssetPricesFromAccounts(List<Pubkey> priceAccounts)async{
    List<PriceData> priceDatas = [];
    final currentSlotPromise = connection.getSlot(config: CommitmentAndMinContextSlotConfig(commitment: commitment));
    final accountInfos = await connection.getMultipleAccounts(priceAccounts, config: GetAccountInfoConfig(commitment: commitment));

    final currentSlot = await currentSlotPromise;
    for (var i = 0; i < priceAccounts.length; i++) {
      // Declare local variable to silence typescript warning; otherwise it thinks accountInfos[i] can be undefined
      final accInfo = accountInfos[i];
      if (accInfo == null) {
        throw Exception("Could not get account info for account ${priceAccounts[i].toBase58()}");
      }

      final baseData = parseBaseData(accInfo.data);
      if (baseData == null || baseData.type != AccountType.Price) {
        throw Exception("Account ${ priceAccounts[i].toBase58() }is not a price account");
      }

      final priceData = parsePriceData(accInfo.data, currentSlot);
      priceDatas.add(priceData);
    }

    return priceDatas;
  }
}