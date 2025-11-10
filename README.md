# Food Safety Sentinel - A TownPass Microservice
## Service Overview

Food Safety Sentinel is a TownPass microservice that delivers timely and personalized food safety information to citizens. It provides features such as querying inspection results for any food establishment, listing nearby locations with failed inspections, displaying night market stall grades and awards, and matching e-receipt records (載具) with businesses to proactively warn users about potential food safety risks. The service updates daily and issues push notifications when new incidents occur near a user's saved addresses or when a user has recently visited a flagged establishment.

## How It Works

The service integrates multiple open data sources and cloud-native components to provide reliable, up-to-date food safety insights:

- **OpenStreetMap (OSM)** powers geospatial visualization for food establishments and night markets within the TownPass app.
- **Scheduled web crawlers** regularly gather food safety announcements and inspection reports published by Taipei City.
- **Google Cloud Storage** acts as the central repository for processed datasets, map overlays, and alert metadata.
- **Dockerized microservices on Cloud Run** handle crawler execution and backend APIs at scale, without server management overhead.
- **Firebase Cloud Messaging (FCM)** delivers proactive push alerts, notifying citizens instantly when new food safety issues are detected.

These components work together to deliver accurate, up-to-date insights about the city’s food safety landscape directly to mobile users.

# What is Town Pass?

Town Pass is an open-source project developed by the Taipei City Government. With the growth of smart cities, the demand for digitalization in city management and citizen services continues to rise. As we enter a new digital era, our goal is to involve citizens in the process, combining third-party expertise and innovation to make digital life in Taipei more convenient.

Town Pass is not just an application; it is an open community project. Through open-source, every citizen can participate in the ideation, development, and optimization of the application. This not only enhances citizen engagement and satisfaction but also leverages collective intelligence to continuously improve the application, making it truly serve the people. Furthermore, we hope that various municipalities can widely adopt the open-source framework of Town Pass, integrate it with their existing municipal service systems, and quickly have their own applications to enhance digital governance.

Open source is a key driver of technological progress and social development. Through open-source, Town Pass will become an ever-evolving platform, attracting developers from all backgrounds to contribute. We welcome experts to submit code, report issues, provide suggestions, and even develop new features and creative ideas, working together to perfect Town Pass as we advance toward a smart city.

# Getting Started

We highly recommend to read through our [document](https://tpe-guideline.web.app/en/docs/) for more detail.

Here are some quick setup guide.

## Requirement

- [Flutter](https://docs.flutter.dev/get-started/install) or [FVM](https://fvm.app/documentation/getting-started/installation)
- [XCode](https://developer.apple.com/xcode/) (for iOS)
- [Android SDK](https://developer.android.com/studio/index.html) (for Android, with or without Android Studio)

## Build the Project

1. Get the packages project needed:

   ```bash
   flutter pub get
   ```
2. Generate additional needed dart code for the project.

   ```bash
   flutter packages pub run build_runner build
   ```
3. You are all set now, Run the project from your IDE or the through the command line:

   ```bash
   flutter run
   ```
