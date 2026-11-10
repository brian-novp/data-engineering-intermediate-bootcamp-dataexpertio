drop table if exists actors_history_scd;

create table actors_history_scd (
    actorid text,                          
    quality_class quality_class,           
    is_active boolean,                      
    start_date integer,                     
    end_date integer,                       
    is_current boolean default true,       
    primary key (actorid, start_date)      
);
