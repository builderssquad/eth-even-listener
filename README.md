# Eth Event Listener 

# by Builderssquad Bloackchain Developers

## Motivation

Make a simple smart contract event listener to get events from the smart contract in NodeJS app and be configure the finality

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


const config = {
    // list of all supported chains and chain specifics
    chains: require("./chains.json"),
    // chosen chain 
    chain: 1,
    // the block where smart contract was deployed
    startBlock: 4634748,
    // contract information of USDT: https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7
    contract: { abi: require('./erc20.abi.json'),
                address : "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                event: "Transfer"
    },
    // required: init an event's handler. if you callback error, it will try to send it again till success - this is mostly all what you need for your app :)
    eventsCallback : (events, cb)=> {
        console.log('incoming unique events', events)
        cb()
    },
    // optional: this callback is triggered between event processing circles, processing starts right after this script is finished
    trialCallback : (cb)=> {
        console.log("start of procssing")
        cb()
    },
}


startSyncService(db, config, (err)=> {  
    console.log("process is terminated, err: " + err ); 
});

```
