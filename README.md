Dart Client for consuming Pyth price data.

## Features
Dart Client for consuming Pyth price data.


## Usage
```
    final pythConnection = PythConnection(
      connection,
      getPythProgramKeyForCluster(cluster.name),
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
```
