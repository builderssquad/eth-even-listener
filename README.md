# Eth Event Listener 

### by Builderssquad Bloackchain Developers

## Motivation

Make a simple smart contract event listener to get events from the smart contract in NodeJS app and be configure the finality

Do not care about internal integrity and be notified about new finalized event inside the nodejs app

## Implementation 

* NodeJS module
* build on top of getPastEvents (https://web3js.readthedocs.io/en/v1.2.11/web3-eth-contract.html#getpastevents)
* Used key-value storage DB to cache the data. if you delete the storage it will replay all transactions. 

Notice! Please use drive storage instead of memory in production


## Dependencies

* levelup db - to keep processing index
* configuration file - to provide info about rpc, confirmation config, contract address, abi and startBlock

## Install 

```
npm i eth-event-listener --save
```

## Example 

See in `test` folder 

``` Javascript
// db dependencies - read more about levelup (https://github.com/Level/awesome) to understand how to configure it
const levelup = require('levelup');
const memdown = require('memdown'); 

// sync service
const { startSyncService } = require('eth-event-listener');

// init a key-value storage db (can be any), 
// here is in example the data is stored in memory, but you can chose different storage
const db = levelup(memdown(), { keyEncoding: 'json' });

const options = {
    // @required: list of all supported chains and chain specifics
    chains: require("./chains.json"),
    // @required: chosen chain from chains list
    chain: 1,
    // @required: contract information of USDT: https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7
    contract: { abi: require('./erc20.abi.json'),
                address : "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                event: "Transfer"
    },// @optional: this callback is triggered between event processing circles, processing starts right after this script is finished
    trialCallback : (cb)=> {
        console.log("start of procssing")
        cb()
    },
    // @required: init an event's handler. 
    // if you callback error, it will try to send it again till success - this is mostly all what you need for your app :)
    // this method will never send duplicated transactions, 
    // possibly it can send the outdated transaction after newer transaction. it depends on blockchain node congested state. please follow the event sourcing pattern to replay such transactions
    eventsCallback : (events, cb)=> {
        console.log('incoming unique events', events)
        // recommendation to use cross-process communication to notify your node app (rebbitMQ, ...)
        cb()
    },
    // @optional: the block where smart contract was deployed
    startBlock: 4634748
    
}

// start it and let it go.
// recommendation to use pm2 and use it as microservice
startSyncService(db, options, (err)=> {  
    console.log("process is terminated, err: " + err ); 
});

```

### Event fields

You can find the information here https://web3js.readthedocs.io/en/v1.2.11/web3-eth-contract.html#contract-events-return

The structure of the returned event Object looks as follows:

* event - String: The event name.
* signature - String|Null: The event signature, null if it’s an anonymous event.
* address - String: Address this event originated from.
* returnValues - Object: The return values coming from the event, e.g. {myVar: 1, myVar2: '0x234...'}.
* logIndex - Number: Integer of the event index position in the block.
* transactionIndex - Number: Integer of the transaction’s index position the event was created in.
* transactionHash 32 Bytes - String: Hash of the transaction this event was created in.
* blockHash 32 Bytes - String: Hash of the block this event was created in. null when it’s still pending.
* blockNumber - Number: The block number this log was created in. null when still pending.
* raw.data - String: The data containing non-indexed log parameter.
* raw.topics - Array: An array with max 4 32 Byte topics, topic 1-3 contains indexed parameters of the event.

Example 


```JSON
[
  {
    event: "Transfer",
    address: "0x8f0483125fcb9aaaefa9209bd576e3cc72697c13",
    returnValues: {
      0: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
      1: "0xD37f430A68dD39C16f0aEf07708a7C1f0dBc6433",
      2: "1000000000000000000",
      from: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
      to: "0xD37f430A68dD39C16f0aEf07708a7C1f0dBc6433",
      value: "1000000000000000000"
    },
    blockNumber: 48,
    transactionHash: "0xc6ef2fc5426d6ad6fd9e2a26abeab0aa2411b7ab17f30a99d3cb96aed1d1055b",
    transactionIndex: 0,
    blockHash: "0x6ef2fc5426d6ad6fd9e2a26abeab0aa2411b7ab17f30a99d3cb96aed1d1055b",
    logIndex: 0,
    removed: false,
    id: "log_1"
  }
]

```
