insert into actors_history_scd
    select
        actorid,                               
        quality_class,                         
        is_active,                             
        min(current_year) as start_date,               
        lead(current_year, 1, 9999) over (             
            partition by actorid               
            order by current_year                      
        ) - 1 as end_date,                      
        case                                  
            when lead(current_year, 1) over (
                    partition by actorid
                    order by current_year
                ) is null then true
            else false
        end as is_current
    from actors
    group by 1, 2, 3, current_year
    order by actorid, start_date;