import ballerina/log;
import ballerinax/googleapis.sheets;
import ballerinax/slack;
import ballerinax/trigger.shopify;

configurable string shopifyApiSecretKey = ?;
configurable int listenerPort = 8090;

configurable string sheetsClientId = ?;
configurable string sheetsClientSecret = ?;
configurable string sheetsRefreshToken = ?;
configurable string sheetsRefreshUrl = "https://oauth2.googleapis.com/token";

configurable string spreadsheetId = ?;
configurable string ordersSheetName = "Orders";

configurable string slackToken = ?;
configurable string slackChannel = ?;

shopify:ListenerConfig listenerConfig = {
    apiSecretKey: shopifyApiSecretKey
};

listener shopify:Listener shopifyListener = new (listenerConfig, listenerPort);

sheets:Client sheetsClient = check new ({
    auth: {
        clientId: sheetsClientId,
        clientSecret: sheetsClientSecret,
        refreshToken: sheetsRefreshToken,
        refreshUrl: sheetsRefreshUrl
    }
});

slack:Client slackClient = check new ({
    auth: {
        token: slackToken
    }
});

# Maps a Shopify order event into a row of values for the Google Sheet.
#
# + event - The Shopify order event payload
# + return - A row of values representing the order
function mapOrderToSheetRow(shopify:OrderEvent event) returns (int|string|decimal|boolean|float)[] => [
    event?.order_number ?: 0,
    event?.name ?: "",
    event?.email ?: "",
    event?.financial_status ?: "",
    event?.fulfillment_status ?: "",
    event?.total_price ?: "",
    event?.currency ?: "",
    event?.created_at ?: ""
];

# Appends a new order row to the shared Google Sheet used for fulfillment tracking.
#
# + event - The Shopify order event payload
# + return - An error if the append operation fails
function appendOrderToSheet(shopify:OrderEvent event) returns error? {
    (int|string|decimal|boolean|float)[] row = mapOrderToSheetRow(event);
    sheets:A1Range a1Range = {
        sheetName: ordersSheetName
    };
    sheets:ValueRange|error result = sheetsClient->appendValue(spreadsheetId, row, a1Range);
    if result is error {
        return result;
    }
}

# Builds a human-readable Slack notification message for a new Shopify order.
#
# + event - The Shopify order event payload
# + return - The formatted Slack message text
function buildOrderNotificationMessage(shopify:OrderEvent event) returns string {
    string orderName = event?.name ?: "";
    string customerEmail = event?.email ?: "";
    string totalPrice = event?.total_price ?: "";
    string currency = event?.currency ?: "";
    string financialStatus = event?.financial_status ?: "";
    return string `:package: New Shopify order ${orderName} received! Total: ${totalPrice} ${currency} | Customer: ${customerEmail} | Payment status: ${financialStatus}`;
}

# Sends a real-time Slack notification with order details to the designated channel.
#
# + event - The Shopify order event payload
# + return - An error if the notification fails to send
function notifySlackChannel(shopify:OrderEvent event) returns error? {
    string message = buildOrderNotificationMessage(event);
    slack:ChatPostMessageResponse|error result = slackClient->/chat\.postMessage.post({
        channel: slackChannel,
        text: message
    });
    if result is error {
        return result;
    }
}

service shopify:OrdersService on shopifyListener {

    # Triggered when a new order is created in Shopify.
    # Appends the order as a row in the shared Google Sheet and
    # sends a real-time Slack notification to the operations team.
    #
    # + event - The Shopify order event payload
    # + return - An error if the downstream operations fail
    remote function onOrdersCreate(shopify:OrderEvent event) returns error? {
        error? sheetResult = appendOrderToSheet(event);
        if sheetResult is error {
            log:printError("Failed to append order to Google Sheet", sheetResult, orderName = event?.name ?: "");
        }

        error? slackResult = notifySlackChannel(event);
        if slackResult is error {
            log:printError("Failed to send Slack notification", slackResult, orderName = event?.name ?: "");
        }
    }

    remote function onOrdersCancelled(shopify:OrderEvent event) returns error? {
        return;
    }

    remote function onOrdersFulfilled(shopify:OrderEvent event) returns error? {
        return;
    }

    remote function onOrdersPaid(shopify:OrderEvent event) returns error? {
        return;
    }

    remote function onOrdersPartiallyFulfilled(shopify:OrderEvent event) returns error? {
        return;
    }

    remote function onOrdersUpdated(shopify:OrderEvent event) returns error? {
        return;
    }
}
