package uk.bit1.mcpserver;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(GreetingController.class)
class GreetingControllerTest {

  @Autowired private MockMvc mockMvc;

  @Test
  void greetsTheWorldByDefault() throws Exception {
    mockMvc
        .perform(get("/greeting"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.message").value("hello, world"));
  }

  @Test
  void greetsTheSuppliedName() throws Exception {
    mockMvc
        .perform(get("/greeting").param("name", "tony"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.message").value("hello, tony"));
  }
}
