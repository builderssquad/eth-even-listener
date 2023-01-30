require! {
    \./web3.ls : { get-contract, create-web3 }
    \./math.ls : { plus, /*minus, div, times*/ }
    \prelude-ls : { map }
    \./helpers/as-callback.ls
    \web3 : Web3
    \moment
    \prelude-ls : { map, unique }
    #\web3-eth-abi : abi
    \superagent : { post, get }
    \base-64 : base64
    \utf8
}




save-event = (db, config, item, cb)->
    err, index-guess <- db.get "events/#{config.contract.event}/index"
    return cb err if err? and err?not-found isnt yes
    index =
        | err?not-found is yes => \0
        | _ => index-guess `plus` 1
    unique-id = "#{item.transaction-hash}/#{item.transaction-index}/#{item.log-index}"
    err <- db.get "events/#{config.contract.event}/known/#{unique-id}"
    return cb err if err? and err?not-found isnt yes
    return cb "Expected error. #{unique-id} is already processed" if err?not-found isnt yes
    #console.log "save event tx #{item.transactionHash}; user: #{item.returnValues?recipient}; value: #{item.returnValues?value};" 
    err <- db.put "events/#{config.contract.event}/indexed/#{index}", item
    return cb err if err?
    err <- db.put "events/#{config.contract.event}/index" , index
    return cb err if err?

    #
    #err <- db.put \events/RegisterUri/last-confirmed-index, index
    #return cb err if err?

    err <- db.put "events/#{config.contract.event}/known/#{unique-id}", index
    return cb err if err?

    cb null

save-events = (db, config, [ item, ...items ], cb)->
    return cb null if not item?
    err <- save-event db, config, item
    console.log "nothing to do with it but error", err if err?
    <- set-immediate
    save-events db, config, items, cb

get-past-events-with-shifts = (config, web3, contract, from-block, to-block, [shift, ...shifts], cb)->
    return cb null, [] if not shift?
    #console.log 'shift', shift , +from-block , +to-block
    err, events <- contract-get-past-events config, web3, contract, config.contract.event, {from-block: +from-block - shift, to-block: +to-block - shift}
    return cb err if err?
    err, rest <- get-past-events-with-shifts config, web3, contract, from-block, to-block, shifts
    return cb err if err?
    all = rest ++ events
    cb null, all

verify-config = (config, cb)->
    return cb "required config" if typeof! config isnt \Object
    return cb "required config.chain" if typeof! config.chain isnt \Number
    return cb "required config.contract" if typeof! config.contract isnt \Object
    return cb "required config.contract-address" if not Web3.utils.isAddress(config.contract.address)
    return cb "events-callback is required" if typeof! config.events-callback isnt \Function
    return cb "config.contract.abi is required" if typeof! config.contract.abi isnt \Array
    return cb "required config.event" if typeof! config.contract.event isnt \String
    return cb "expected config.chains" if typeof! config.chains isnt \Object
    cb null    

get-past-events-for-index = (config, rpc-index, from-block, to-block, cb)->
    err <- verify-config config
    return cb err if err?
    err, web3 <- create-web3 config.chain, { ...config , rpc-index }
    return cb err if err?
    err, contract <- get-contract web3, config.contract.abi, config.contract.address
    return cb err if err?
    shifts = if +to-block - +from-block > 50 then [0] else [50, 0]
    get-past-events-with-shifts config, web3, contract, from-block, to-block , shifts, cb


export get-past-events = (config, from-block, to-block, cb)->
    err <- verify-config config
    return cb err if err?
    return cb "+from-block is NaN" if isNaN +from-block
    return cb "+to-block is NaN" if isNaN +to-block
    return cb "get-past-events from-block: #{from-block} is higher than to-block: #{to-block}" if +from-block > +to-block
    err, events <- get-past-events-for-index config, 1, from-block, to-block
    return cb null, events if not err?
    err, events <- get-past-events-for-index config, 2, from-block, to-block
    return cb null, events if not err?
    cb err
    

check-finalized = (db, config, confirmations, block-number, cb)->
    err <- verify-config config
    return cb err if err?
    return cb null if confirmations > 0
    err, web3 <- create-web3 config.chain, { ...config , rpc-index: 1 }
    return cb err if err?
    err, data <- web3.eth.getBlock(block-number.toString!)
    #console.log "check finalized block #{data?number}. Block is finalized #{data?isFinalized}"
    return cb err if err?
    return cb null if data?isFinalized is true
    cb "block is not finalized"

confirm-events = (db, config, last-known-block, cb)->
    err <- verify-config config
    return cb err if err?
    err, last-confirmed-index-guess <- db.get "events/#{config.contract.event}/index/confirmed"
    return cb err if err? and err?not-found isnt yes
    last-confirmed-index =
        | err?not-found is yes => \-1
        | _ => last-confirmed-index-guess
    next-confirmed-index = last-confirmed-index `plus` 1
    err, item <- db.get "events/#{config.contract.event}/indexed/#{next-confirmed-index}"
    return cb err if err? and err?not-found isnt yes
    return cb "nothing to confirm. expected new event at index #{next-confirmed-index}" if err?not-found is yes
    confirmations = config.chains[config.chain].confirmation-needed
    err <- check-finalized db, config, confirmations, item.block-number
    return cb null if err?
    #console.log "confirmations", +item.block-number , +last-known-block - confirmations
    return cb null if +item.block-number > +last-known-block - confirmations
    err <- db.put "events/#{config.contract.event}/index/confirmed" , next-confirmed-index
    return cb err if err?
    <- set-immediate
    confirm-events db, config, last-known-block, cb

# network actions start

subscription-data =
    init: false

subscription = (err, event)->
    return if err?
    subscription-data.latest-block = event.number
    subscription-data.latest-update = moment.utc!.unix!
    

ensure-block-subscription = (config)->
    return null if subscription-data.init == true
    subscription-data.init = true
    return null if not config.chains[config.chain].wss?
    web3 = new Web3(config.chains[config.chain].wss.0)
    web3.eth.subscribe \newBlockHeaders , subscription


recently-updated-block = (config)->
    ensure-block-subscription config
    return false if not subscription-data?
    return false if not subscription-data.latest-block?
    return false if not subscription-data.latest-update?
    return false if moment.utc!.unix! - subscription-data.latest-update > 10
    return true

get-block-from-websockets = (cb)->
    return cb "required cb" if typeof! cb isnt \Function
    #console.log \get-block-from-websockets , subscription-data.latest-block
    cb null, subscription-data.latest-block

/*
stringify-result = (obj)->
    return "null" if not obj?
    JSON.stringify obj
*/
try-parse = (text, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    try
        cb null, JSON.parse(text)
    catch err
        cb err

get-body = (model, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    #return cb null, model.body if model.body?
    try-parse model.text, cb

make-simple-post = (config, host, req, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    err, model <- post(host, req).timeout({ deadline: 60000 }).end
    return cb err if err?
    cb null, model

make-proxy-post = (config, host, req, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    #auth = base64.encode(utf8.encode("#{config.proxy.login}:#{config.proxy.password}"))
    #.set("Proxy-Authorization", "Basic #{auth}")
    err, model <- post(host, req).proxy(config.proxy.address).timeout({ deadline: 60000 }).end
    return cb err if err?
    cb null, model

make-post = (config, host, req, cb)->
    return cb "required host" if typeof! host isnt \String
    return cb "required request" if typeof! req isnt \Object
    return cb "required cb" if typeof! cb isnt \Function
    make-proxy-post config, host, req, cb if config.proxy?
    make-simple-post config, host, req, cb

make-request-internal = (config, method, params, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    err <- verify-config config
    return cb err if err?
    err, web3 <- create-web3 config.chain, config
    make-request.id = make-request.id ? 1
    make-request.id += 2
    return cb err if err?
    req =  { jsonrpc : \2.0 , method , params , id : make-request.id }
    err, model <- make-post config, web3.currentProvider.host, req
    return cb err if err?
    err, body <- get-body model
    return cb err if err?
    #console.log "expected body", { ...req, host: web3.currentProvider.host }, body, model.text if not body?result?
    return cb "expected body" if not body?result?
    #return cb "#{config.maker.chain} expected model.body.result for #{web3.currentProvider.host} -> #{stringify-result(req)}, got #{stringify-result model.body}" 
    cb null, body.result

make-request-trials = (trials, config, method, params, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    err <- verify-config config
    return cb err if err?
    err, data <- make-request-internal config, method, params
    return cb null, data if not err?
    return cb err if err? and err isnt 'expected body'
    return cb err if trials is 0
    <- set-timeout _, 1000
    next-trials = trials - 1
    make-request-trials next-trials, config, method, params, cb

make-request = (config, method, params, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    make-request-trials 3, config, method, params, cb

try-parse-int = (data, cb)->
    return cb "required cb" if typeof! cb isnt \Function
    try
        cb null, parse-int(data, 16)
    catch err
        cb err
# rpc index 0

get-block-number = (config, cb)->
    err <- verify-config config
    return cb err if err?
    return cb null, get-block-number.cached-block if get-block-number.cached-block? and config.partial-load is yes
    return get-block-from-websockets cb if recently-updated-block config
    err, data <- make-request { ...config , rpc-index: 1 }, \eth_blockNumber , []
    return cb err if err? 
    err, block <- try-parse-int data
    console.log \eth_blockNumber, block
    return cb err if err?
    get-block-number.cached-block = block
    cb null, block




# rpc index 1
contract-get-past-events = (config, web3, contract, eventname, params, cb)->
    err <- verify-config config
    return cb err if err?
    err, events <- as-callback contract.get-past-events(eventname , params)
    console.log "get events #{params.from-block} -> #{params.to-block} (#{ +params.to-block - +params.from-block } blocks); total events: #{events?length}; error: #{err?}; partial load #{config.partial-load is yes}"
    return cb "RPC ERROR #{web3.currentProvider?host}: getPastEvents #{eventname}(#{params.from-block},#{params.to-block}) = #{err.message ? err}" if err?
    cb null, events
    
    #topic = abi.encodeEventSignature("CrossSwap(address,uint256,uint256,uint256)")
    #param =
    #    fromBlock : Web3.utils.toHex(params.from-block)
    #    toBlock : Web3.utils.toHex(params.to-block) 
    #    topics : [topic]
    #    address : contract._address
    #err, res <- make-request { ...config , rpc-index: 1 }, \eth_getLogs , [param]
    #contract._decodeEventABI res

web3-get-transaction-receipt = (config, rpc-index, hash, cb)->
    #console.log 'web3-get-transaction-receipt'
    #err, web3 <- create-web3 config.maker.chain, { ...config , rpc-index }
    #err, res <- web3.eth.get-transaction-receipt hash
    #return cb err if err?
    #cb null, res
    make-request { ...config , rpc-index }, \eth_getTransactionReceipt , [hash], cb
    

get-transaction-receipt-multi = (config, hash, rpc-index, cb)->
    err <- verify-config config
    return cb err if err?
    return cb null, [] if rpc-index is -1
    err, res <- web3-get-transaction-receipt config, rpc-index, hash
    return cb err if err?
    next-rpc-index = rpc-index - 1
    err, data <- get-transaction-receipt-multi config, hash, next-rpc-index
    return cb err if err?
    all = [res] ++ data
    cb null, all

validate-all-results = (all, cb)->
    return cb "unexpected result. any rpc in config?" if all.length is 0
    return cb null if all.length is 1
    items =
        all |> map (-> it.status) |> unique
    return cb "expected the same status everywhere" if items.length > 1
    cb null

# do not spam node if it returned right transaction
get-block-with-cache = (web3, blocknumber, cb)->
    key = web3.currentProvider.host + "_" +  blocknumber
    return cb null, get-block-with-cache[key] if get-block-with-cache[key]? 

    err, block <- web3.eth.get-block blocknumber
    return cb err if err?
    get-block-with-cache[key] = block
    cb null, block


process-case-when-transaction-is-not-available = (err, config, item, cb)->
    return cb err if err isnt 'expected body'
    <- set-timeout _, 5000
    err, web3 <- create-web3 config.chain, { ...config , rpc-index: 1 }
    return cb err if err?

    err, block <- get-block-with-cache web3, item.block-number.to-string!
    return cb err if err?
    return cb "expected transactions" if typeof! block?transactions isnt \Array
    #
    # script this transcation because it was forgotten
    #
    return cb "expected body" if block.transactions.index-of(item.transaction-hash) is -1
    console.log "transaciton is available in block. but get transaction receipt returns null"
    
    get-transaction-receipt config, item, cb
    

# rpc index all
get-transaction-receipt = (config, item, cb)-> 
    err <- verify-config config
    return cb err if err?
    rpc-index = config.chains[config.chain].rpc.length - 1
    err, all <- get-transaction-receipt-multi config, item.transaction-hash, rpc-index
    return process-case-when-transaction-is-not-available err, config, item, cb if err?
    err <- validate-all-results all
    return cb err if err?
    cb null, all.0

    

# network actions end


init-new-known-block = (db, config, to-block, cb)->
    to-block-save = config.start-block ? to-block
    console.log "init first start block", to-block-save
    db.put "events/#{config.contract.event}/last-known-block" , to-block-save , cb
    

export sync-with-chain = (db, config, cb)->
    err <- verify-config config
    return cb err if err?
    err, to-block-guess <- get-block-number config
    return cb err if err?
    err, synced-block-guess <- db.get "events/#{config.contract.event}/last-known-block"
    return cb err if err? and err?not-found isnt yes
    return init-new-known-block db, config, to-block-guess, cb if err?
    #console.log "to-block-guess", to-block-guess
    last-known-block =
        | err?not-found is yes => to-block-guess # this is first run only
        | _ => synced-block-guess
    # we do want to sync known block
    #console.log \last-known-block, last-known-block
    # one more protection to be sure that next block number is higher than previous known block number
    return cb "last-known-block #{last-known-block} should be lower than to-block-guess #{to-block-guess}" if +last-known-block > +to-block-guess
    # reduce block range to match rate limits 
    next-block = last-known-block  #`plus` 1
    count = 200
    partial-load = +to-block-guess - +last-known-block > count
    to-block =
        if partial-load
        then +last-known-block + count
        else +to-block-guess
    <- set-immediate
    err, events <- get-past-events config, next-block, to-block
    #console.log \sync-with-chain , 5
    #console.log err, events
    return cb err, partial-load if err?
    # todo check why plus
    #next-block = to-block `plus` 1
    #console.log \sync-with-chain , 6
    err <- db.put "events/#{config.contract.event}/last-known-block" , to-block
    return cb err, partial-load if err?
    #console.log \sync-with-chain , 7
    err <- save-events db, config, events
    #console.log \sync-with-chain , 8
    return cb err, partial-load if err?
    #console.log \sync-with-chain , 9
    err <- confirm-events db, config, to-block
    return cb err, partial-load if err?
    #console.log \sync-with-chain , 10
    cb null, partial-load
    
validate-event = (db, config, item, cb)->
    err <- verify-config config
    return cb err if err?
    return cb "expected item" if typeof! item isnt \Object
    return cb "expected item.return-values" if typeof! item.return-values isnt \Object
    #return cb "expected nft address" if typeof! item.return-values.address isnt \String
    #return cb "expected website uri" if typeof! item.return-values.uri isnt \String

    err, receipt <- get-transaction-receipt config, item
    return cb err if err?
    return cb "reverted transaction" if receipt.status is false
    cb null

get-range-of-events = (db, config, start, end, cb)->
    err <- verify-config config
    return cb err if err?
    #console.log \get-range-of-events, start , end
    return cb \overflow if +start > +end
    err, item <- db.get "events/#{config.contract.event}/indexed/#{start}"
    return cb err if err? and err?not-found isnt yes
    return cb "expected crosswap by index #{start} for get-range-of-events" if err?not-found is yes
    err <- validate-event db, config, item
    return cb err if err? and err not in ["reverted transaction", "expected body", "already"]
    current = [item]
    # process only one by one
    return cb null, { index: start, items: current } if current.length > 0 and config.escalation-mode is \slow
    <- set-immediate
    next-start = start `plus` 1
    err, rest <- get-range-of-events db, config, next-start, end
    return cb null, { index: start, items: current } if err in ["overflow"]
    return cb err if err?
    items = current ++ rest.items
    cb null, { rest.index, items }


update-host-state = (db, config, items, cb)->
    cb "not implemented"


process-range-of-events = (db, config, result, cb)->
    err <- verify-config config
    return cb err if err?
    err <- verify-config config
    return cb err if err?
    return cb "required object" if typeof! result isnt \Object
    { index, items } = result
    err <- config.events-callback items
    return cb err if err?
    err <- db.put "events/#{config.contract.event}/index/#{config.chain}/processed", index
    return cb err if err?
    cb null, items.length


export process-events = (db, config, cb)->
    err <- verify-config config
    return cb err if err?
    err <- verify-config config 
    return cb err if err?
    err, latest-index <- db.get "events/#{config.contract.event}/index/confirmed"
    return cb err if err? and err?not-found isnt yes
    return cb null, 0 if err?not-found is yes
    err, last-processed-index-guess <- db.get "events/#{config.contract.event}/index/#{config.chain}/processed"
    return cb err if err? and err?not-found isnt yes
    last-processed-index =
        | err?not-found is yes => \-1
        | _ => last-processed-index-guess
    return cb null, 0 if +last-processed-index is +latest-index
    next-process-index = last-processed-index `plus` 1
    #err, web3 <- create-web3 config.taker.chain, { ...config , rpc-index: 2 }
    #return cb err if err?
    #
    err, result <- get-range-of-events db, config, next-process-index, latest-index
    return cb err if err?
    process-range-of-events db, config, result, cb



process-trial-callback-if-any = (db, config, cb)->
    return cb null if typeof! config.trial-callback isnt \Function
    err <- config.trial-callback
    return cb err if err?  
     
    cb null

export start-sync-service = (db, config, cb)->
    err <- process-trial-callback-if-any db, config
    return cb err if err?
    
    err <- verify-config config
    return cb err if err?
    
    err, partial-load <- sync-with-chain db, config
    console.log err if err?
    #return try-wait-because-of-rate-limit start-sync-service, db, config, cb if err?
    delay = config.chains[config.chain].block-time-sec * 1000
    interval = 
        | partial-load is true => 1
        | delay > 3000 => delay
        | _ => 3000
    <- set-timeout _, interval
    err <- process-events db, config
    console.log err if err?
    #cb null #exit from app and restart it to reduce memory leaks
    start-sync-service db, { ...config, partial-load } , cb

