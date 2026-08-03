const actual = require("@actual-app/api");

const { ACTUAL_SERVER_URL, ACTUAL_PASSWORD, ACTUAL_SYNC_ID } = process.env;

async function main() {
  await actual.init({
    dataDir: "/tmp",
    serverURL: ACTUAL_SERVER_URL,
    password: ACTUAL_PASSWORD,
  });

  await actual.downloadBudget(ACTUAL_SYNC_ID);

  const accounts = await actual.getAccounts();
  let failures = 0;

  for (const account of accounts) {
    if (account.closed) continue;
    try {
      console.log(`Syncing account: ${account.name}`);
      await actual.runBankSync({ accountId: account.id });
    } catch (err) {
      failures += 1;
      console.error(`Failed to sync account ${account.name}: ${err.message}`);
    }
  }

  await actual.shutdown();

  if (accounts.length > 0 && failures === accounts.length) {
    throw new Error("All account syncs failed");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
