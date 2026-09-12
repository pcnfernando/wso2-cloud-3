import ballerina/log;

public function main() returns error? {
    do {
        log:printInfo("Hello");
    } on fail error e {
        log:printError("Error occurred", 'error = e);
        return e;
    }
}
