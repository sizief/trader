const https = require('https')
const dotenv = require('dotenv');
dotenv.config();
console.log(process.env.NOBITEX_USERNAME)
function call(data){

  const payload = JSON.stringify(data)

  const options = {
    hostname: 'api.nobitex.ir',
    port: 443,
    path: '/market/orders/list',
    method: 'POST',
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

const data = {
  order: "-price",
  type: "sell",
  dstCurrency: "rls",
  srcCurrency: "btc"
}
call(data)
