# This file exports `send-transaction` to main app.

require! {
  \ethereumjs-tx : \Tx
  \ethereumjs-util : \eth-util
  \web3 : \Web3
  \bignumber.js : BN
  \./math.ls : { div, times } # math + - * / functions to work with large numbers
  \ethereum-address
  \fs : { read-file, read-file-sync }
  \./helpers/as-callback.ls
  \superagent : { post }
}
# convert decimal to hex
numToHex = (inputBn) ->
    ethUtil.addHexPrefix(new BN(inputBn ? 0).toString(16))

# get rpc address from the config
get-rpc = (chain, config)->
  index = config.rpc-index ? 0
  rpc = config.chains[chain].rpc
  res =
    | typeof! rpc is \Array and rpc[index]? => rpc[index]
    | typeof! rpc is \Array => rpc.0
    | typeof! rpc is \String => rpc
    | typeof! rpc is \Object => rpc
    | _ => null
  res




# setup provider based on the config. 
# url for external provider
# object for ganache

export get-provider = (chain, config)->
  rpc = get-rpc chain, config
  return null if typeof! rpc not in <[String Object]>
  return new Web3.providers.HttpProvider(rpc) if typeof! rpc is \String and rpc.index-of('http') is 0
  return new Web3.providers.WebsocketProvider(rpc) if typeof! rpc is \String and rpc.index-of('ws') is 0
  return cb "ganache is not supported" if typeof! rpc is \Object
  return null

setup-provider = (chain, config, web3, cb)->
  return cb "config is required" if typeof! config isnt \Object
  provider = get-provider(chain, config)
  return cb "provider is required" if not provider?
  web3.set-provider(provider)
  cb null, web3


get-env-privatekey = ->
  return get-env-privatekey.key if get-env-privatekey.key?
  get-env-privatekey.key = JSON.parse(read-file-sync "./.env.private-key", "utf8").key
  get-env-privatekey.key

# create web3 instance from the private key
export create-web3 = (chain, config, cb)->
  return cb "config is required" if typeof! config isnt \Object
  private-key = config.chains[chain].private-key
  web3 = new Web3!
  err <- setup-provider chain, config, web3
  return cb err if err?
  return cb null, web3 if typeof! private-key isnt \String
  address = \0x + eth-util.private-to-address(Buffer.from(private-key, 'hex')).to-string \hex
  web3.eth.default-account = address
  # --- required for testnet/mainnet and can be skipped for ganache
  account = web3.eth.accounts.private-key-to-account real-private-key
  web3.eth.accounts.wallet.add account
  


  #web3.eth.get-block-number 

  # ---
  #web3.eth.send-transaction = ({ to, value, data }, cb)->
  #  console.log \send
  #  send-transaction { config, to, value, data }, cb
  #web3.eth.send-transaction = send-transaction private-key
  cb null, web3
  

# use it for getTransactionReceipt asking on few nodes
export create-web3-with-private-key = (chain, config, private-key, cb)->
  return cb "config is required" if typeof! config isnt \Object
  return cb "private-key is required" if typeof! private-key isnt \String
  web3 = new Web3!
  address = \0x + eth-util.private-to-address(Buffer.from(private-key, 'hex')).to-string \hex
  err <- setup-provider chain, config, web3
  return cb err if err?
  
  web3.eth.default-account = address
  # --- required for testnet/mainnet and can be skipped for ganache
  account = web3.eth.accounts.privateKeyToAccount private-key
  web3.eth.accounts.wallet.add account
  # ---
  #web3.eth.send-transaction = ({ to, value, data }, cb)->
  #  console.log \send
  #  send-transaction { config, to, value, data }, cb
  cb null, web3



try-get-receipt = ({ web3, tx-hash }, cb)->
  <- set-timeout _, 2000
  err, tx-receipt <- web3.eth.get-transaction-receipt tx-hash
  return cb err if err?
  return try-get-receipt { web3, tx-hash } , cb if not tx-receipt?
  cb null, tx-receipt

get-address = (web3, tx-hash, cb) ->
  err, tx <- web3.eth.get-transaction tx-hash
  return cb err if err?
  return cb "Tx is not mined yet." if not tx?block-number?
  err, tx-receipt <- try-get-receipt { web3, tx-hash }
  return cb err if err?
  return cb "tx receipt is not found" if not tx-receipt?
  #return cb "Tx is mined, but contract is not created yet." if not txReceipt.contract-address?
  tx.contract-address = txReceipt.contract-address
  cb null, tx

export try-get-address = (web3, tx-hash, cb) ->
  #console.log "TX #{tx-hash}"
  err, data <- get-address web3, tx-hash
  return cb null, data if not err?
  return cb err if err? and err isnt "Tx is not mined yet."
  <- set-timeout _, 3000
  err, data <- try-get-address web3, tx-hash
  cb err, data

get-nonce = (web3, cb)->
  err, nonce <- web3.eth.get-transaction-count web3.eth.default-account, \pending
  return cb err if err?
  cb null, nonce



export get-balance = ({ chain, config, address }, cb)->
  #return cb "Private Key is required" if not config.private-key?
  err, web3 <- create-web3 chain, config
  return cb err if err?
  err, value <- web3.eth.get-balance address
  return cb err if err?
  amount = value `div` (10^18)
  cb null, amount




# get instance of the contract (TODO: remove)
#export get-contract = ({ chain, config, abi, address, contract }, cb)->
#  #this line is added to optimize the case when contract is needed few times but wrapped by another function
#  return cb null, contract if typeof! contract is \Object
#  return cb "config is required" if typeof! config isnt \Object
#  return cb "abi is required" if typeof! abi isnt \Array
#  return cb "address is required" if typeof! address isnt \String
#  err, web3 <- create-web3 chain, config
#  return cb err if err?
#  data = new web3.eth.Contract(abi, address)
#  data.from = web3.eth.default-account
#  cb null, data


export get-contract = (web3, abi, address, cb)->
  return cb "web3 is required" if not web3?
  return cb "required the contract abi" if typeof! abi isnt \Array
  return cb "required correct ethereum address, got #{address}" if not Web3.utils.isAddress(address)
  #err, source-code <- get-source-code name
  #return cb err if err?
  # { object, abi } = source-code
  data = new web3.eth.Contract(abi, address)
  cb null, data

export get-abi = (name, cb)->
    err, abi-content <- read-file "#{name}.abi.json", \utf8
    return cb err if err?
    abi = JSON.parse abi-content 
    cb null, abi

export get-source-code = (name, cb)->
    err, abi <- get-abi name
    return cb err if err?
    err, bytecode-content <- read-file "#{name}.bytecode.json", \utf8
    return cb err if err?
    object = JSON.parse(bytecode-content).object
    cb null, { abi, object }


make-request = (web3, method, params, cb)->
    req = { jsonrpc : \2.0 , method , params , id :1 }
    err, model <- post web3.currentProvider.host, req .end
    return cb err if err?
    #console.log model
    return cb "expected model.body.result" if not model?body
    cb null, model.body.result


# deploy the smart contract (TODO: remove)
export deploy-contract = ({ chain, config, source-code, args }, cb)->
  return cb "config is required" if typeof! config isnt \Object
  return cb "source code is required object" if typeof! source-code isnt \Object
  { object, abi } = source-code
  return cb "source-code.object is required" if typeof! object isnt \String
  return cb "source-code.abi is required" if typeof! abi isnt \Array
  return cb "args is required" if typeof! args isnt \Array
  err, web3 <- create-web3 chain, config
  return cb err if err?
  deploy-data = new web3.eth.Contract(abi).deploy({ data: "0x"+ object, arguments: args }) 
  #console.log 'deploy from', web3.eth.default-account
  #data = deploy-data.encodeABI({ data: "0x"+ object, arguments: args })
  
  #err, data <- web3.eth.sendTransaction { data }
  #return cb err if err?
  #return data
  #err, txhash <- make-request web3, "eth_sendRawTransaction", [data]
  #return cb err if err? 
  
  #return cb "tx hash #{txhash}"
  err, contract <- as-callback deploy-data.send({ from: web3.eth.default-account, gas: \5900000 })
  #console.log "is err", err?
  return cb err if err?
  address = contract.options.address
  cb null, address


