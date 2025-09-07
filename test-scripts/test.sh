#!/bin/bash

flow project deploy

echo "Creating Accounts"
flow accounts create --key 02063b160efa1b14d44bf2476ef3c9dccd10653f07adec9af147ca8dbfb013adcf1841fb2828e079758a13146e0d08c4230ae2a7a5da62d157ec638b7ff8f44a
flow accounts create --key c6c9003bed804ae5c0e231ceaf7d8008130c01da67995b2f167b753175ca5a11ea47366df835de47cba7a456086d4c77c79001520e23d33e378454b5e6accf65
flow accounts create --key 814b3a8ff8cba27e975e80b4d78ec439307f7f51ddefda9ad2a373a99a824683333ca4816d1329b6ff2931dcb6668f8caa9a155e5655aa5c79ad42ccee2f7556
#above accounts were only needed temporarily, real accounts below
flow accounts create --key 61010e062e9b28430d192f9ea5da1c480ba3c9605ca22438b40052a2fd0dc0443676fa0179fa4565620b7b4e9cc358487c3f4bf1e90ba667f5fe954a9a9c0cf8
#flow accounts create --key 9ffc3f25883116fc099d4561c0ab800dd5941718ae34afa7accb680aaffa95c1ca609cc702f9000393fce674781b664f29302b464b9c828c150280639c35a1c4
#flow accounts create --key d3c27f9560976f101de9f8052614fd167d72503b2aa2e27301039faea0a35bdbc1970d08d3e4b1c0f98b5af3cb81f4a22167fea82f360f4832059cfd44e6c0b1
#flow accounts create --key f8650ee3025cd7dd55891ae27a1136326aceaf9a68e20e88569f23d4daa16fe337e92bd1c8081c6ab5ecb9f07a31487b7a00401eef2fca89d6543864efd8f409
#flow accounts create --key f22fb36fa0fc05212e9ded7b0cb6d3c33a9635ceb86923f764871b05b94dbb3cc280fc27f1060ea871916394b9e9a4ce3d03dbff2d7d4c9f1a28bd2342f7c741
#flow accounts create --key 8fb0dd6898d978054b7a9fa2423a92c9a7c358038333a9d515febf15d6067e15c71ae82c633718dc708162e4b159097e4340144623c6a36f109623997ec9260a #4deaad9d72f28c51c9080ae8a821893881ae7117072075ac2513bfb4aca88f1b, 0xeb179c27144f783c

#transfer flow
echo "Transfer Flow"
flow transactions send cadence/transactions/TransferFlow.cdc '0x045a1763c93006ca' 1000.0 
#flow transactions send cadence/transactions/TransferFlow.cdc '0x120e725050340cab' 1000.0
#flow transactions send cadence/transactions/TransferFlow.cdc '0xf669cb8d41ce0c74' 1000.0
#flow transactions send cadence/transactions/TransferFlow.cdc '0x192440c99cb17282' 1000.0
#flow transactions send cadence/transactions/TransferFlow.cdc '0xfd43f9148d4b725d' 1000.0

#set up organization
flow transactions send /Users/cjcarnicle/aiSports/dev/Cascade/Cadence/cadence/transactions/add_organization.cdc "TESTORG" 0xf8d6e0586b0a20c7

#read account to see original balance
echo "Original Balance"
flow accounts get 0x045a1763c93006ca

#create & scheduleagent
flow transactions send /Users/cjcarnicle/aiSports/dev/Cascade/Cadence/cadence/transactions/create_and_schedule_registration.cdc 1 "TESTORG" 10.0 "10s" 0.0 nil 1 1000 --signer emulator-account-1

echo "Balance after creating and scheduling agent:"
sleep 1
flow accounts get 0x045a1763c93006ca

#wait for 15 seconds
echo "Waiting for 15 seconds"
sleep 15

#read account to see new balance
echo "Balance after 15 seconds:"
flow accounts get 0x045a1763c93006ca