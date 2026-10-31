package uk.bit1.mcpserver;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreetingController {

  @GetMapping("/greeting")
  public Greeting greet(@RequestParam(defaultValue = "world") String name) {
    return new Greeting("hello, " + name);
  }

  public record Greeting(String message) {}
}
