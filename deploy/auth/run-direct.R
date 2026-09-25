# The isolated gateway is the only admitted transport peer. No host port exists.
app<-source('/srv/shiny-server/delphyr/app.R',local=new.env(parent=globalenv()))$value
shiny::runApp(app,host='0.0.0.0',port=3860,launch.browser=FALSE)
