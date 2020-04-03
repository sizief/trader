const https = require('https')
const dotenv = require('dotenv');
dotenv.config();

function call(params){

  const payload = JSON.stringify(params.data)

  const options = {
    hostname: 'api.nobitex.ir',
    port: 443,
    path: params.path,
    method: params.method,
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': payload.length
    }
  }

  const req = https.request(options, res => {
    console.log(`statusCode: ${res.statusCode}`)

    res.on('data', d => {
      process.stdout.write(d)
    })
  })

  req.on('error', error => {
    console.error(error)
  })

  req.write(payload)
  req.end()
}

function orders(){
  call({
    method: "POST",
    path: "/market/orders/list",
    data: {
      order: "-price",
      type: "sell",
      dstCurrency: "rls",
      srcCurrency: "btc"
    }
  })
}

function authenticate(){
  call({
    method: "POST",
    path: "/auth/login/",
    data: {
      username: process.env.NOBITEX_USERNAME,
      password: process.env.NOBITEX_PASSWORD
    }
  })
}

//orders()
authenticate()
