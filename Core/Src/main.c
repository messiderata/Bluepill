#include <stdint.h>
#include "stm32f1xx.h"


void HardFault_Handler();

int main(void)
{

  GPIOC_PCLOCK_EN();
  

  while (1)
  {

  }
}


void HardFault_Handler(){


  int test =0;

  test |= test;

}