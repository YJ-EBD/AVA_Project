import '../../messenger/presentation/messenger_page.dart';
import '../../messenger/domain/messenger_models.dart';

class HomePage extends MessengerPage {
  const HomePage({super.key, super.initialTab});

  const HomePage.avaStock({super.key})
    : super(initialTab: MessengerTab.avaStock);

  const HomePage.calendar({super.key})
    : super(initialTab: MessengerTab.calendar);
}
