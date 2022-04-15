#import "Enmity.h"

// Create a response to a command
NSDictionary* createResponse(NSString *uuid, NSString *data) {
  NSDictionary *response = @{
    @"id": uuid,
    @"data": data
  };

  return response;
}

// Send a response back
void sendResponse(NSDictionary *response) {
  NSError *err; 
  NSData *data = [NSJSONSerialization
                    dataWithJSONObject:response
                    options:0
                    error:&err];

  if (err) {
    return;
  }

  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSString *responseString = [NSString stringWithFormat: @"%@%@", ENMITY_PROTOCOL, [json stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
  NSURL *url = [NSURL URLWithString:responseString];

  NSLog(@"json: %@", json);

  [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

// Validate that a command is using the Enmity scheme
BOOL validateCommand(NSString *command) {
  BOOL valid = [command containsString:@"enmity"];

  if (!valid) {
    NSLog(@"Invalid protocol");
  }

  return valid;
}

// Clean the received command
NSString* cleanCommand(NSString *command) {
  NSString *json = [[command 
            stringByReplacingOccurrencesOfString:ENMITY_PROTOCOL
            withString:@""]
          stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

  NSLog(@"json: %@", json);

  return json;
}

// Parse the command
NSDictionary* parseCommand(NSString *json) {
  NSURLComponents* components = [[NSURLComponents alloc] initWithString:json];
  NSArray *queryItems = components.queryItems;

  NSMutableDictionary *command = [[NSMutableDictionary alloc] init];

  for (NSURLQueryItem *item in queryItems) {
    if ([item.name isEqualToString:@"id"]) {
      command[@"id"] = item.value;
    }

    if ([item.name isEqualToString:@"command"]) {
      command[@"command"] = item.value;
    }

    if ([item.name isEqualToString:@"params"]) {
      command[@"params"] = [item.value componentsSeparatedByString:@","];
    }
  }

  return [command copy];
}

// Handle the command
void handleCommand(NSDictionary *command) {
  NSString *name = [command objectForKey:@"command"];
  if (name == nil) {
    return;
  }

  NSString *uuid = [command objectForKey:@"id"];
  NSArray *params = [command objectForKey:@"params"];

  // Install a plugin
  if ([name isEqualToString:@"install-plugin"]) {
    NSURL *url = [NSURL URLWithString:params[0]];
    if (!url || ![[url pathExtension] isEqualToString:@"js"]) {
      return;
    }

    NSString *pluginName = getPluginName(url);
    NSString *title = [[NSString alloc] init];
    NSString *message = [[NSString alloc] init];
    if (checkPlugin(pluginName)) {
      title = @"Plugin already exists";
      message = [NSString stringWithFormat:@"Are you sure you want to overwrite %@?", pluginName];
    } else {
      title = @"Install plugin";
      message = [NSString stringWithFormat:@"Are you sure you want to install %@?", pluginName];
    }

    confirm(title, message, ^() {
      BOOL success = installPlugin(url);
      if (success) {
        if ([uuid isEqualToString:@"-1"]) {
          alert([NSString stringWithFormat:@"%@ has been installed! :D", pluginName]);
          return;
        }

        sendResponse(createResponse(uuid, [NSString stringWithFormat:@"**%@** has been installed! :D", pluginName]));
        return;
      }

      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"An error occured while installing %@.", pluginName]);
        return;
      }

      sendResponse(createResponse(uuid, [NSString stringWithFormat:@"An error occured while installing *%@*.", pluginName]));
    });

    return;
  }

  if ([name isEqualToString:@"uninstall-plugin"]) {
    NSString *pluginName = params[0];

    BOOL exists = checkPlugin(pluginName);
    if (!exists) {
      sendResponse(createResponse(uuid, [NSString stringWithFormat:@"**%@** currently isn't installed.", pluginName]));
      return;
    }

    confirm(@"Uninstall plugin", [NSString stringWithFormat:@"Are you sure you want to uninstall %@?", pluginName], ^() {
      BOOL success = deletePlugin(pluginName);
      if (success) {
        sendResponse(createResponse(uuid, [NSString stringWithFormat:@"**%@** has been uninstalled.", pluginName]));
        return;
      }

      sendResponse(createResponse(uuid, [NSString stringWithFormat:@"An error occured while removing *%@*.", pluginName]));
    });
  }

  if ([name isEqualToString:@"install-theme"]) {
    NSURL *url = [NSURL URLWithString:params[0]];
    BOOL success = installTheme(url);
    if (success) {
      sendResponse(createResponse(uuid, @"Theme has been installed! :D"));
      return;
    }

    sendResponse(createResponse(uuid, @"An error occured while installing the theme."));
  }

  if ([name isEqualToString:@"uninstall-theme"]) {
    BOOL success = uninstallTheme(params[0]);
    if (success) {
      sendResponse(createResponse(uuid, @"Theme has been uninstalled."));
      return;
    }

    sendResponse(createResponse(uuid, @"An error occured while uninstalling the theme."));
  }

  if ([name isEqualToString:@"apply-theme"]) {
    setTheme(params[0], params[1]);
    sendResponse(createResponse(uuid, @"Theme has been applied! :D"));
  }

  if ([name isEqualToString:@"remove-theme"]) {
    setTheme(nil, nil);
    sendResponse(createResponse(uuid, @"Theme has been removed! :D"));
  }

  if ([name isEqualToString:@"enable-plugin"]) {
    BOOL success = enablePlugin(params[0]);
    sendResponse(createResponse(uuid, success ? @"yes" : @"no"));
  }

  if ([name isEqualToString:@"disable-plugin"]) {
    BOOL success = disablePlugin(params[0]);
    sendResponse(createResponse(uuid, success ? @"yes" : @"no"));
  }
}

%hook AppDelegate

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {  
  NSString *input = url.absoluteString;
	if (!validateCommand(input)) {
    %orig;
    return true;
	}

	NSString *json = cleanCommand(input);
  NSDictionary *command = parseCommand(json);
  handleCommand(command);

  return true;
}

%end