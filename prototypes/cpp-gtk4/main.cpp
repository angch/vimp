#include <gtkmm.h>

class HelloWorld : public Gtk::Window
{
public:
  HelloWorld();
  virtual ~HelloWorld();

protected:
  //Member widgets:
  Gtk::Button m_button;
};

HelloWorld::HelloWorld()
: m_button("Hello World")   // creates a new button with label "Hello World".
{
  // Sets the border width of the window.
  set_margin(10);

  // When the button receives the "clicked" signal, it will call the
  // on_button_clicked() method defined below.
  m_button.signal_clicked().connect([] () {
    std::cout << "Hello World" << std::endl;
  });

  // This packs the button into the Window (a container).
  set_child(m_button);
}

HelloWorld::~HelloWorld()
{
}

int main(int argc, char *argv[])
{
  auto app = Gtk::Application::create("org.gtkmm.example");

  //Shows the window and returns when it is closed.
  return app->make_window_and_run<HelloWorld>(argc, argv);
}
