as-callback = (p, cb)->
    timer =
        ref: null
        cb : cb
    clear = ->
        clear-timeout timer.ref
    handle = ->
        clear!
        cb = timer.cb
        timer.cb = ->
        cb "callback timeout is reached"
    timer.ref = set-timeout handle, 60000
    try 
        p.then (result)->
            clear!
            return timer.cb null, result
        p.catch (result)->
            clear!
            return timer.cb result
    catch err
        clear!
        timer.cb err
        
module.exports = as-callback