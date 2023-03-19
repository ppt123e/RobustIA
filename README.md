# RobustIA
## The R package for the manucript "Robust time selection for interim analysis in the Bayesian phase 2 exploratory clinical trial"


## Installation
```r
library("devtools")
install_github("ppt123e/RobustIA",force=TRUE)
library("RobustIA")
```
## Example
In a single-arm phase 2 exploratory clinical trial with ORR as endpoint, assume the null hypothesis is H0: θ ≤ 0.3, the alternative hypothesis is H1: θ > 0.3, the maximum sample size is 40, and the prior distribution for θ follows Beta (0.3,0.7). For the Bayesian decision rule, we set P_c, P_e, and P_f as 0.8. In addition, the enrolment rate follows Uniform (0,1), the enrolment period is 12 months, the maximum follow-up time for a patient is 12 months, and time to response follows exponential distribution. The IA is planned at Dk and the candidate k ranges from 10-35. Only Go decision is considered.

```r
Uscore(
  Nmax=40,
  enroll_time=12,
  follow_time=12,
  theta0=0.3,
  theta1=0.4,
  Pc=0.8,
  Pe=0.8,
  Pf=0.8,
  l=4,
  a=0.3,
  b=0.7,
  start=10,
  end=35,
  gamma=1,
  w=1,
  monitor_type='',
  n_simu=10000
)
```
