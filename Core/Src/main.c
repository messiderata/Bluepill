#include <stdint.h>

int main(void)
{
  volatile uint32_t test = 5U;

  while (1)
  {
    test = test + test;
  }
}
