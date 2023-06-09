library('stringr')
library('dplyr')
library('parallel')
cl <- makeCluster(detectCores())
clusterEvalQ(cl,library(dplyr))
clusterEvalQ(cl,library(stringr))


####Threshold for Bayesian decision rule
critic_end=function(theta0,Nmax,a,b,Pc){
  i=0
  while (1-pbeta(theta0,i+a,Nmax-i+b)<Pc){
    i=i+1
  }
  j=Nmax
  while (pbeta(theta0,j+a,Nmax-j+b)<Pc){
    j=j-1
  }
  return(c(i,j))
}


f=function(theta,n_after_response,n_after,a,b,interim_response,n_interim){
  return(dbinom(n_after_response,n_after,theta)*dbeta(theta,a+interim_response,b+n_interim-interim_response))
}

f1=function(x,n_after,a,b,interim_response,n_interim){
  tmp=integrate(f,0,1,n_after_response=x,n_after=n_after,a=a,b=b,interim_response=interim_response,n_interim=n_interim)
  return(tmp[[1]])
}


res=function(n_interim,interim_response,Nmax,a,b,i,j){
  n_after=Nmax-n_interim
  zz=seq(0,n_after,1)
  pp=mapply(f1,zz,n_after,a,b,interim_response,n_interim)
  ppn=cbind(zz,pp)
  No_Go=round(sum(ppn[zz<=j-interim_response,'pp']),3)
  Go=round(sum(ppn[zz>=i-interim_response,'pp']),3)
  return(c(Go,No_Go))
}


critical=function(n_interim,Pf,Pe,Nmax,a,b,i,j){
  interim_response=seq(0,n_interim,1)
  data_res=data.frame()
  for (k in interim_response){
    data_res=rbind(data_res,c(k,res(n_interim=n_interim,interim_response=k,Nmax,a,b,i,j)))
  }
  no_go=max(data_res[data_res[,3]>Pf,][,1])
  go=min(data_res[data_res[,2]>Pe,][,1])
  return(c(no_go,go))
}


critic1_func=function(Nmax,theta0,Pc,Pe,Pf,a,b,n_interim){
  dec=critic_end(theta0,Nmax,a,b,Pc)
  dec1=dec[1]
  dec2=dec[2]
  n_interim1=as.integer(str_split(n_interim,','))
  data_critic=data.frame(t(mapply(critical,n_interim1,Pf,Pe,Nmax,a,b,dec1,dec2)))
  data_critic1=cbind(n_interim,data_critic)
  return(data_critic1)
}

#########Simulation data
generate_data1_par=function(X,N,enroll_time,follow_time,shape,scale){
  enroll=runif(N,0,enroll_time)
  time_to_response=rweibull(N,shape,scale)
  response=ifelse(time_to_response<follow_time,1,0)
  total_time=enroll+time_to_response
  res_simu=data.frame(id=seq(1,N,1),enroll=enroll,time_to_response=time_to_response,response=response,total=total_time)
  res_simu=arrange(res_simu,enroll)
  return(res_simu)
}


base_final4=function(res_simu,threshold_go,threshold_nogo,interim){
  n_interim=length(interim)
  tmp=sapply(interim,function(x){sum(res_simu[['response']][1:x])})
  tmp1_go=ifelse(tmp>=threshold_go,1,0)
  tmp1_nogo=ifelse(tmp<=threshold_nogo,-1,0)
  tmp1=tmp1_go+tmp1_nogo
  final_decision1=ifelse(tmp1[n_interim]==1,'Success','Fail')
  return(c(tmp1,final_decision1))
}


######Predicative value
condition1=function(x,cutoff){
  return(length(which(x==1))>=cutoff)
}


condition2=function(x,cutoff){
  return(length(which(x==-1))>=cutoff)
}


#####Metrics
metrics=function(X,res_df_cp1,l,condition,...){
  indexes=colnames(res_df_cp1)
  index=which(indexes==str_c('interim_',X))
  tmp=table(res_df_cp1[,str_c('interim_',X)],res_df_cp1[,'final'])
  tmp1=as.data.frame.matrix(tmp)
  tmp2=tmp1[row.names(tmp1)=='1',]
  ppv=as.numeric(tmp2[2]/sum(tmp2))
  pos=res_df_cp1[res_df_cp1[,str_c('interim_',X)]==1,]
  pre_pos_tmp=apply(pos[,seq(index-l,index-1)],1,condition,...)
  after_pos_tmp=apply(pos[,seq(index+1,index+l)],1,condition,...)
  stable=mean(pre_pos_tmp & after_pos_tmp)
  return(c(ppv,stable))
}

metrics0=function(X,res_df_cp0,l,condition,...){
  indexes=colnames(res_df_cp0)
  index=which(indexes==str_c('interim_',X))
  tmp=table(res_df_cp0[,str_c('interim_',X)],res_df_cp0[,'final'])
  tmp1=as.data.frame.matrix(tmp)
  tmp2=tmp1[row.names(tmp1)=='-1',]
  npv=as.numeric(tmp2[1]/sum(tmp2))
  neg=res_df_cp0[res_df_cp0[,str_c('interim_',X)]==-1,]
  pre_neg_tmp=apply(neg[,seq(index-l,index-1)],1,condition,...)
  after_neg_tmp=apply(neg[,seq(index+1,index+l)],1,condition,...)
  stable=mean(pre_neg_tmp & after_neg_tmp)
  return(c(npv,stable))
}


#' Generate U score and its components for each candidate IA timing
#' @param Nmax Maximum sample size for the trial
#' @param enroll_time Estimated duration for patient enrollment
#' @param follow_time Estimated maximum follow-up time for each patient
#' @param theta0 ORR (Overall Response Rate) for external control in the single-arm phase 2 exploratory clinical trial
#' @param theta1 ORR (Overall Response Rate) for the new treatment
#' @param Pc  Threshold to reject or not reject the null hypothesis at final analysis
#' @param Pe  Threshold for Go decision at interim analysis
#' @param Pf  Threshold for No-Go decision at interim analysis
#' @param l   Period to consider in the calculation of stability value
#' @param a   First parameter for Beta prior distribution
#' @param b   Second parameter for Beta prior distribution
#' @param start Start of the candidate IA timing, required to >=2
#' @param end   End of the candidate IA timing,required to <= Nmax-l
#' @param gamma Gamma parameter of Weibull distribution for time to response data in the simulation
#' @param w     Weight on Go decision at interim analysis, ranging from 0-1
#' @param n_simu Number of trials to simulate
#' @return A data frame containing U score and its components (P1k,S1k,P2k,S2k) for each IA timing
#' @export

Uscore=function(Nmax,enroll_time,follow_time,theta0,theta1,Pc,Pe,Pf,l,a,b,start,end,gamma,w,n_simu=10000){
  interim=seq(2,Nmax,1)
  n_interim=interim[1:(length(interim)-1)]
  interim_num=length(n_interim)
  critic_design=critic1_func(Nmax,theta0,Pc,Pe,Pf,a,b,n_interim)
  dec=critic_end(theta0,Nmax,a,b,Pc)
  dec1=dec[1]
  dec2=dec[2]
  threshold_go=c(critic_design[['X2']],dec1)
  threshold_nogo=c(critic_design[['X1']],dec2)
  lambda1=follow_time/exp(log(-log(1-theta1))/gamma)
  lambda0=follow_time/exp(log(-log(1-theta0))/gamma)
  #######Statistics under H1
  simu_data1=parLapply(cl,X=1:n_simu,fun=generate_data1_par,N=Nmax,enroll_time=enroll_time,follow_time=follow_time,shape=gamma,scale=lambda1)
  res_df_cp=parLapply(cl,X=simu_data1,fun=base_final4,threshold_go=threshold_go,threshold_nogo=threshold_nogo,interim=interim)
  res_df_cp1=data.frame(do.call(rbind,res_df_cp))
  colnames(res_df_cp1)=c(str_c('interim',interim[1:length(interim)],sep='_'),c('final'))
  metrics1=parLapply(cl,X=start:end,fun=metrics,res_df_cp1=res_df_cp1,l=l,condition=condition1,cutoff=l)
  metrics2=data.frame(do.call(rbind,metrics1))
  metrics2['IA']=start:end
  metrics2[,'information']=metrics2['IA']/Nmax*100
  metrics2[,'score']=metrics2[,'X1']*metrics2[,'X2']
  metrics2=arrange(metrics2,desc(score))
  colnames(metrics2)=c('P1k','S1k','IA','Information','P1k*S1k')
  #####Statistics under H0
  simu_data0=parLapply(cl,X=1:n_simu,fun=generate_data1_par,N=Nmax,enroll_time=enroll_time,follow_time=follow_time,shape=gamma,scale=lambda0)
  res_df_cp0=parLapply(cl,X=simu_data0,fun=base_final4,threshold_go=threshold_go,threshold_nogo=threshold_nogo,interim=interim)
  res_df_cp0=data.frame(do.call(rbind,res_df_cp0))
  colnames(res_df_cp0)=c(str_c('interim',interim[1:length(interim)],sep='_'),c('final'))
  metrics0=parLapply(cl,X=start:end,fun=metrics0,res_df_cp0=res_df_cp0,l=l,condition=condition2,cutoff=l)
  metrics0=data.frame(do.call(rbind,metrics0))
  metrics0['IA']=start:end
  metrics0[,'score']=metrics0[,'X1']*metrics0[,'X2']
  colnames(metrics0)=c('P2k','S2k','IA','P2k*S2k')
  res_all=left_join(metrics2,metrics0,by='IA')
  res_all[,'Uscore']=w*res_all[,'P1k*S1k']+(1-w)*res_all[,'P2k*S2k']
  res_all=res_all[,c('IA','Information','P1k','S1k','P1k*S1k','P2k','S2k','P2k*S2k','Uscore')]
  res_all=arrange(res_all,desc(Uscore))
  return(res_all)
}

