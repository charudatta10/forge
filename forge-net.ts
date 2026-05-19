#!/usr/bin/env bun

const cmd = process.argv[2]

switch (cmd) {
  case "peer-id":
    console.log("peer-local-dev")
    break

  case "announce":
    console.log("announced", process.argv[3])
    break

  case "peers":
    console.log("[]")
    break

  case "fetch":
    console.log("fetching", process.argv[3])
    break

  case "gossip":
    console.log("gossip", process.argv[3], process.argv[4])
    break

  default:
    console.log("unknown command")
}