import 'dart:math';
import 'dart:typed_data';

import 'package:solana_web3/buffer.dart';
import 'package:solana_web3/solana_web3.dart';

const constantMagic = 0xa1b2c3d4;
const version2 = 2;
const version = version2;
// /** int of slots that can pass before a publisher's price is no longer included in the aggregate. */
const MAX_SLOT_DIFFERENCE = 25;

enum PriceStatus {
  Unknown,
  Trading,
  Halted,
  Auction,
  Ignored,
}
 enum CorpAction {
  NoCorpAct,
}

 enum PriceType {
  Unknown,
  Price,
}

 enum DeriveType {
  Unknown,
  Volatility,
}

 enum AccountType {
  Unknown,
  Mapping,
  Product,
  Price,
  Test,
  Permission,
}

// final empty32Buffer = ByteBuffer.asByteBuffer(32);
final Buffer empty32Buffer = Buffer(32);
var pubkeyOrNull = (Buffer data) => (data == empty32Buffer ? null : Pubkey.fromUint8List(data.asUint8List()));

AccountInfo<U> recreateAccountInfo<U extends Object>(AccountInfo account,U data){
  return AccountInfo<U>(lamports: account.lamports,
   owner: account.owner, data: data, executable: account.executable,
    rentEpoch: account.rentEpoch);
}

 class Base {
  num magic;
  num version;
  AccountType type;
  num size;
  Base(this.magic,this.version,this.type,this.size);
}

 class MappingData extends Base {
  Pubkey? nextMappingAccount;
  List<Pubkey> productAccountKeys;
  MappingData(int magic,int version,AccountType type,int size,this.nextMappingAccount,this.productAccountKeys):super(magic,version,type,size);
}

//  class Product {
  // [index: string]: string
// }
typedef Product = Map<String,String>;
// typedef Product = dynamic;

 class ProductData extends Base {
  Pubkey? priceAccountKey;
  Product product;
  ProductData(int magic,num version,AccountType type,num size,this.priceAccountKey,this.product)
    :super(magic,version,type,size);
}

 class Price {
  BigInt priceComponent;
  num price;
  BigInt confidenceComponent;
  num confidence;
  PriceStatus status;
  CorpAction corporateAction;
  num publishSlot;

  Price(this.priceComponent,this.price,this.confidenceComponent,this.confidence,this.status,this.corporateAction,this.publishSlot);
}

 class PriceComponent {
  PriceComponent(
  Pubkey publisher,
  Price aggregate,
  Price latest);
}

// /**
//  * valueComponent = numerator / denominator
//  * value = valueComponent * 10 ^ exponent (from PriceData)
//  */
 class Ema {
  BigInt valueComponent;
  num value;
  BigInt numerator;
  BigInt denominator;
  Ema(this.valueComponent,this.value,this.numerator,this.denominator);
}

 class PriceData extends Base {
  PriceType priceType;
  num exponent;
  num numComponentPrices;
  num numQuoters;
  BigInt lastSlot;
  BigInt validSlot;
  Ema emaPrice;
  Ema emaConfidence;
  BigInt timestamp;
  num minPublishers;
  num drv2;
  num drv3;
  num drv4;
  Pubkey productAccountKey;
  Pubkey? nextPriceAccountKey;
  BigInt previousSlot;
  BigInt previousPriceComponent;
  num previousPrice;
  BigInt previousConfidenceComponent;
  num previousConfidence;
  BigInt previousTimestamp;
  List<PriceComponent> priceComponents;
  Price aggregate;
  // The current price and confidence and status. The typical use of this class is to consume these three fields.
  // If undefined, Pyth does not currently have price information for this product. This condition can
  // happen for various reasons (e.g., US equity market is closed, or insufficient publishers), and your
  // application should handle it gracefully. Note that other raw price information fields (such as
  // aggregate.price) may be defined even if this is undefined; you most likely should not use those fields,
  // as their value can be arbitrary when this is undefined.
  num? price;// | undefined
  num? confidence;// | undefined
  PriceStatus status;
  PriceData(
    num magic,
    num version,
    AccountType type,
    size,
    this.priceType,
    this.exponent,
    this.numComponentPrices,
    this.numQuoters,
    this.lastSlot,
    this.validSlot,
    this.emaPrice,
    this.emaConfidence,
    this.timestamp,
    this.minPublishers,
    this.drv2,
    this.drv3,
    this.drv4,
    this.productAccountKey,
    this.nextPriceAccountKey,
    this.previousSlot,
    this.previousPriceComponent,
    this.previousPrice,
    this.previousConfidenceComponent,
    this.previousConfidence,
    this.previousTimestamp,
    this.aggregate,
    this.priceComponents,
    this.price,
    this.confidence,
    this.status,
  ):super(magic,version,type,size);
}

 class PermissionData extends Base {
  Pubkey masterAuthority;
  Pubkey dataCurationAuthority;
  Pubkey securityAuthority;
  PermissionData(num magic,num version,AccountType type,num size,this.masterAuthority,this.dataCurationAuthority,this.securityAuthority)
    :super(magic,version,type,size);
}
String dataSliceToString(Buffer data,int offset,int length){
  return String.fromCharCodes(data.slice(offset,length));
}

Pubkey dataSliceToPubKey(Buffer data,int offset,int length){
    return Pubkey.fromUint8List(data.slice(offset,length).asUint8List());
}

// /** Parse data as a generic Pyth account. Use this method if you don't know the account type. */
 Base? parseBaseData(Buffer data){
  // data is too short to have the magic number.
  // if (data.lengthInBytes < 4) {
  if (data.length < 4) {
    return null;
  }

  final magic = data.getUint32(0);
  if (magic == constantMagic) {
    // program version
    final version = data.getUint32(4);
    // account type
    final AccountType type = AccountType.values.firstWhere((e) => e.index == data.getUint32(8));
    // account used size
    final size = data.getUint32(12);
    return  Base(magic,version,type,size);
  } else {
    return null;
  }
}
var parseMappingData = (Buffer data){  // MappingData => {
  // pyth magic number
  final magic = data.getUint32(0);
  // program version
  final version = data.getUint32(4);
  // account type
    final AccountType type = AccountType.values.firstWhere((e) => e.index == data.getUint32(8));
  // account used size
  final size = data.getUint32(12);
  // int of product accounts
  final numProducts = data.getUint32(16);
  final nextMappingAccount = pubkeyOrNull(data.slice(24, 32));
  // read each symbol account
  var offset = 56;
  final List<Pubkey> productAccountKeys = [];
  for (var i = 0; i < numProducts; i++) {
    final productAccountKey = dataSliceToPubKey(data, offset, 32);
    offset += 32;
    productAccountKeys.add(productAccountKey);
  }
  return MappingData(
    magic,
    version,
    type,
    size,
    nextMappingAccount,
    productAccountKeys,
  );
};

 var parseProductData = (Buffer data){
  // pyth magic number
  final magic = data.getUint32(0,Endian.little);
  // program version
  final num version = data.getUint32(4,Endian.little);
  // account type
  final AccountType type = AccountType.values.firstWhere((e) => e.index == data.getUint32(8,Endian.little));
  // price account size
  final size = data.getUint32(12,Endian.little);
  // first price account in list
  final priceAccountBytes = data.slice(16,32);
  final priceAccountKey = pubkeyOrNull(priceAccountBytes);
  final Product product = {} ;
  if (priceAccountKey != null) product["price_account"] = priceAccountKey.toBase58();
  var idx = 48;
  while (idx < size) {
    final keyLength = data[idx];
    idx++;
    if (keyLength > 0) {
      final key = dataSliceToString(data, idx, keyLength);
      idx += keyLength;
      final valueLength = data[idx];
      idx++;
      final value = dataSliceToString(data, idx, valueLength);
      idx += valueLength;
      product[key] = value;
    }
  }
  return  ProductData( magic, version, type, size, priceAccountKey, product );
};

var parseEma = (Buffer data, int exponent){
  // current value of ema
  final valueComponent = data.getBigInt(0,8);

  final value = num.parse(valueComponent.toString()) * pow(10,exponent);
  // numerator state for next update
  final numerator = data.getBigInt(8,8);
  // denominator state for next update
  final denominator = data.getBigInt(16,8);
  return Ema(
    valueComponent,
    value,
    numerator,
    denominator
     );
};

var parsePriceInfo = (Buffer data,int exponent){
  // aggregate price
  final priceComponent = data.getBigInt(0,8);
  final price = num.parse(priceComponent.toString()) * pow(10 , exponent);
  // aggregate confidence
  final confidenceComponent = data.getBigUint(8,8);
  final confidence = confidenceComponent.toDouble() * pow(10 ,exponent);
  // aggregate status
  final PriceStatus status = PriceStatus.values.firstWhere((e) => e.index ==  data.getUint32(16));
  // aggregate corporate action
  final CorpAction corporateAction =CorpAction.values.firstWhere((e) => e.index == data.getUint32(20));
  // aggregate publish slot. It is converted to int to be consistent with Solana's library class (Slot there is number)
  final publishSlot = data.getUint64(24);
  return Price(
    priceComponent,
    price,
    confidenceComponent,
    confidence,
    status,
    corporateAction,
    publishSlot.toInt()
  );
};

// Provide currentSlot when available to allow status to consider the case when price goes stale. It is optional because
// it requires an extra request to get it when it is not available which is not always efficient.
 var parsePriceData = (Buffer data,int? currentSlot){//}: PriceData => {
  // pyth magic number
  final magic = data.getUint32(0);
  // program version
  final version = data.getUint32(4);
  // account type
  final type = AccountType.values.firstWhere((element) => element.index == data.getUint32(8));
  // price account size
  final size = data.getUint32(12);
  // price or calculation type
  final PriceType priceType = PriceType.values.firstWhere((e) => e.index == data.getUint32(16));
  // price exponent
  final exponent = data.getInt32(20,Endian.little);
  // int of component prices
  final numComponentPrices = data.getUint32(24);
  // int of quoters that make up aggregate
  final numQuoters = data.getUint32(28);
  // slot of last valid (not unknown) aggregate price
  final lastSlot = data.getBigUint(32,8);// readBigUInt64LE(data, 32);
  // valid on-chain slot of aggregate price
  final validSlot = data.getBigUint(40,8);// readBigUInt64LE(data, 40);
  // exponential moving average price
  final emaPrice = parseEma(data.slice(48, 24), exponent);
  // exponential moving average confidence interval
  final emaConfidence = parseEma(data.slice(72, 24), exponent);
  // timestamp of the current price
  final timestamp =data.getBigUint(96,8);// readBigInt64LE(data, 96);
  // minimum int of publishers for status to be TRADING
  final minPublishers = data.getUint8(104);
  // space for future derived values
  final drv2 = data.getInt8(105);
  // space for future derived values
  final drv3 = data.getInt16(106);
  // space for future derived values
  final drv4 = data.getInt32(108);
  // product id / reference account
  final productAccountKey = dataSliceToPubKey(data, 112, 32);
  // next price account in list
  final nextPriceAccountKey = pubkeyOrNull(data.slice(144, 32));
  // valid slot of previous update
  final previousSlot = data.getBigUint(176,8);// readBigUInt64LE(data, 176);
  // aggregate price of previous update
  final previousPriceComponent = data.getBigInt(184,8);// readBigInt64LE(data, 184);
  final previousPrice = num.parse(previousPriceComponent.toString()) * pow(10 , exponent);
  // confidence interval of previous update
  final previousConfidenceComponent = data.getBigUint(192,8);// readBigUInt64LE(data, 192);
  final previousConfidence = previousConfidenceComponent.toDouble() * pow(10 , exponent);
  // space for future derived values
  final previousTimestamp = data.getBigInt(200,8);// readBigInt64LE(data, 200);
  final Price aggregate = parsePriceInfo(data.slice(208, 32), exponent);

  var status = aggregate.status;

  if (currentSlot != null && status == PriceStatus.Trading) {
    if (currentSlot - aggregate.publishSlot > MAX_SLOT_DIFFERENCE) {
      status = PriceStatus.Unknown;
    }
  }

  num? price;
  num? confidence;
  if (status == PriceStatus.Trading) {
    price = aggregate.price;
    confidence = aggregate.confidence;
  }

  // price components - up to 32
  final List<PriceComponent> priceComponents = [];
  var offset = 240;
  while (priceComponents.length < numComponentPrices) {
    final publisher = dataSliceToPubKey(data, offset, 32);
    offset += 32;
    final componentAggregate = parsePriceInfo(data.slice(offset, 32), exponent);
    offset += 32;
    final latest = parsePriceInfo(data.slice(offset, 32), exponent);
    offset += 32;
    priceComponents.add(PriceComponent( publisher, componentAggregate , latest ));
  }

  final priceData = PriceData(
    magic,
    version,
    type,
    size,
    priceType,
    exponent,
    numComponentPrices,
    numQuoters,
    lastSlot,
    validSlot,
    emaPrice,
    emaConfidence,
    timestamp,
    minPublishers,
    drv2,
    drv3,
    drv4,
    productAccountKey,
    nextPriceAccountKey,
    previousSlot,
    previousPriceComponent,
    previousPrice,
    previousConfidenceComponent,
    previousConfidence,
    previousTimestamp,
    aggregate,
    priceComponents,
    price,
    confidence,
    status,
  );
  return priceData;
};

 var parsePermissionData = (Buffer data){//}: PermissionData => {
  // pyth magic number
  final magic = data.getUint32(0);
  // program version
  final version = data.getUint32(4);
  // account type
  final type = AccountType.values.firstWhere((element) => element.index == data.getUint32(8));
  // price account size
  final size = data.getUint32(12);
  final masterAuthority = dataSliceToPubKey(data, 16, 32);
  final dataCurationAuthority = dataSliceToPubKey(data, 48, 32);
  final securityAuthority = dataSliceToPubKey(data, 80, 32);
  return PermissionData(
    magic,
    version,
    type,
    size,
    masterAuthority,
    dataCurationAuthority,
    securityAuthority,
  );
};