async function main() {
  const Token = await artifacts.require("Token");
  const token = await Token.new();
  const accounts = await web3.eth.getAccounts();

  console.log("\n=== DEMO: Dividend Compounding ===\n");

  // Setup
  await token.mint({ value: 50, from: accounts[0] });
  await token.mint({ value: 50, from: accounts[1] });
  await token.transfer(accounts[2], 25, { from: accounts[0] });

  console.log("Initial state:");
  console.log(`  Alice (${await token.balanceOf(accounts[0])} tokens)`);
  console.log(`  Bob (${await token.balanceOf(accounts[1])} tokens)`);
  console.log(`  Charlie (${await token.balanceOf(accounts[2])} tokens)`);

  // First dividend
  await token.recordDividend({ value: 1000, from: accounts[5] });

  console.log("\nAfter first dividend (1000 ETH):");
  console.log(
    `  Alice: ${await token.getWithdrawableDividend(accounts[0])} ETH`
  );
  console.log(`  Bob: ${await token.getWithdrawableDividend(accounts[1])} ETH`);
  console.log(
    `  Charlie: ${await token.getWithdrawableDividend(accounts[2])} ETH`
  );

  // Transfer and mint
  await token.transfer(accounts[2], 25, { from: accounts[1] });
  await token.mint({ value: 75, from: accounts[1] });
  await token.burn(accounts[9], { from: accounts[0] });

  console.log("\nAfter transfers:");
  console.log(
    `  Alice (${await token.balanceOf(accounts[0])} tokens) - burned all`
  );
  console.log(
    `  Bob (${await token.balanceOf(accounts[1])} tokens) - minted more`
  );
  console.log(
    `  Charlie (${await token.balanceOf(accounts[2])} tokens) - received more`
  );

  // Second dividend
  await token.recordDividend({ value: 90, from: accounts[5] });

  console.log("\nAfter second dividend (90 ETH):");
  console.log(
    `  Alice: ${await token.getWithdrawableDividend(
      accounts[0]
    )} ETH (preserved!)`
  );
  console.log(`  Bob: ${await token.getWithdrawableDividend(accounts[1])} ETH`);
  console.log(
    `  Charlie: ${await token.getWithdrawableDividend(accounts[2])} ETH`
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
