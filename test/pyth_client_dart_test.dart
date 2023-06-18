import 'package:flutter_test/flutter_test.dart';

import 'package:pyth_client_dart/pyth_client_dart.dart';
import 'package:solana_web3/solana_web3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Create a connection to the devnet cluster.
  final cluster = Cluster.devnet;
  final connection = Connection(cluster);
  final pythProgramKey = getPythProgramKeyForCluster(cluster.name);

  test('pyth network connect sample', () async{
    final pythConnection = PythConnection(
      connection,
      pythProgramKey,
      null
    );

    pythConnection.onPriceChange((product, price){
      if (price.price != null && price.confidence != null){
        print("${product["symbol"]}: ${price.price} \xB1${price.confidence}");
      } else {
        print("${product["symbol"]}: price currently unavailable. status is ${price.status}");
      }
    });
    await  pythConnection.start();
    await Future.delayed(const Duration(seconds: 3));
  });

  test('pyth http connection', ()async{
    PythHttpClient client = PythHttpClient(connection, pythProgramKey);
    final list = await client.getData();
    print(list.products);
  });
}
